# -*- coding: utf-8 -*-
import sys

from PySide6.QtCore import *
from PySide6.QtNetwork import *

import os
import shutil

import socket
import _thread, time
import hashlib
import base64
import json

from controller.ProjectController import ProjectController
from command.ScriptCommands import ScriptGraphicsProtocol

from view.OutputWindow import OutputWindow 

class RemoteClient(QTcpSocket):
	_instance = None
	_isInit   = False
	
	def __new__(cls, *args, **kwargs):
		if RemoteClient._instance: 
			RemoteClient._disconnect_()

		if not RemoteClient._instance:
			RemoteClient._instance = super(RemoteClient,cls).__new__(cls,*args,**kwargs)

		return RemoteClient._instance

	def __init__(self,parent):
		if RemoteClient._isInit : 
			return 
		RemoteClient._isInit = True

		super(RemoteClient,self).__init__(parent)

		self.status = 0
		self.live = False

		self.clean = False

		self.order = None
		self.payloadSize = None
		self.payload = None
		self.playScene = None
		self.startLine = None

		self._connect_try = 3

		self.readyRead.connect(self.onRead)
		self.disconnected.connect(self.onDisconnect)
		self.connected.connect(self.onConnected)

	def _connect(self,ip,port,clean,count=3):
		if self.playScene == None:
			self.playScene = "scene/메인.lnx";
		print("remoteclient._connect() => ",self.playScene)
		
		self.HOST = ip
		self.PORT = port
		self.clean = clean
		self._connect_try = count

		self.status = 2

		if self.live : 
			QTimer.singleShot(100,self.run)
		else:
			self.tryCount=0
			QTimer.singleShot(100,self.TryConnect)

	def onConnected(self):
		self.live = True
		OutputWindow().notice("테스트 실행 연결.")
		self.run()

	def TryConnect(self):
		self.tryCount += 1
		if self.tryCount > self._connect_try : 
			OutputWindow().notice("테스터와의 연결이 실패하였습니다.")
			RemoteClient._disconnect_()
			return
			
		self.connectToHost(self.HOST,self.PORT);
		if self.waitForConnected(5000):
			pass
		else:
			self.live = False
			QTimer.singleShot(1500,self.TryConnect)
			OutputWindow().notice("연결중...")

	def checksum(self,fpath):
		# 엔진 쪽(src/main.lua)은 to_base64(md5.sumhexa(data)) 로 계산한다.
		# 즉 "md5 16진 문자열을 base64" 한 값이라 digest() 가 아니라 hexdigest() 여야 한다.
		# py3 에서는 hexdigest() 가 str 이므로 b64encode 에 넘기려면 bytes 로 바꿔야 하고,
		# 결과도 bytes 라서 다시 str 로 되돌려야 json 직렬화가 된다.
		hexa = hashlib.md5(open(fpath, 'rb').read()).hexdigest()
		return base64.b64encode(hexa.encode("ascii")).decode("ascii")

	def OnRecved(self,order,size,payload):
		print("OnRecved(self,)",order,size,payload)
		# payload 는 bytes 다. py2 에서는 str 이라 그대로 썼지만 py3 에서는 디코드해야 한다.
		if order == "ulst" :
			self.OnUpdateFiles(json.loads(payload.decode("utf-8")))
		elif order == "ufin":
			self.status = 0
		elif order == "PATH" :
			self.remote_writable_path = payload.decode("utf-8")
			if self.clean : 
				self.ClearRemoteDist()
			self.SendFileList()

			print(self.remote_writable_path)

	def OnUpdateFiles(self,flist):
		self.updateFlist = flist
		self.OnNextUpdateFiles()

	def OnNextUpdateFiles(self):
		if len(self.updateFlist) > 0 :
			v = self.updateFlist[0]
			fullpath = self.BUILDPATH + v
			relative = os.path.dirname(v)
			filename = os.path.basename(v)

			self.sendFile(fullpath,relative,filename)

			if len(self.updateFlist) > 1:
				self.updateFlist = self.updateFlist[1:]
			else:
				self.updateFlist = []

			QTimer.singleShot(1,self.OnNextUpdateFiles)

		else:
			FILES = ScriptGraphicsProtocol().lua.globals().FILES
			slashProjPath = self.PROJPATH.replace("\\","/")
			slashPlayScene = self.playScene.replace("\\","/")
			playScene = slashPlayScene.replace(slashProjPath+"/","")
			byte = QByteArray()
			line = self.startLine
			if line == None:
				line = 0
			print("line=",line)
			# 4바이트 고정 필드. QByteArray.resize() 로 늘린 부분은 초기화가 보장되지 않으므로
			# 직접 0 으로 채운다. 엔진 쪽은 tonumber(recv(input,4)) 로 읽으며 NUL 패딩을 허용한다.
			startLine = QByteArray.number(line)
			startLine.append(b"\x00" * (4 - startLine.size()))
			byte.append(startLine)
			# FILES 는 lua 테이블에서 온 값이라 lupa 가 bytes 로 준다 (str 이면 인코딩).
			sceneFile = FILES[playScene]
			if isinstance(sceneFile, str) :
				sceneFile = sceneFile.encode("utf-8")
			byte.append(QByteArray(sceneFile))
			self.send("ufin", byte )

	def run(self):
		self.status = 1
		self.send("PATH",QByteArray(b"AA"))

	def ClearRemoteDist(self):
		shutil.rmtree(self.remote_writable_path)
		os.makedirs(self.remote_writable_path)

	def SendFileList(self):
		self.PROJPATH = ProjectController().path
		self.IMGPATH  = self.PROJPATH + "/image/"
		self.SCENEPATH = self.PROJPATH + "/scene/"
		self.BUILDPATH = self.PROJPATH + "/build/"

		fileList = {}
		for base, dirs, names in os.walk(self.BUILDPATH):
			for name in names :
				fullpath = os.path.join(base, name)
				relative = base.replace(self.BUILDPATH,"")
				extension= os.path.splitext(name)
				
				ID = relative+"/"+extension[0]+extension[1]
				if ID == "/o" or extension[1] == ".obj" :
					continue
					
				ID = ID[1:] if ID.startswith("/") else ID
				fileList[ID] = self.checksum(fullpath)

		checksums = json.dumps(fileList)

		self.send("flst",QByteArray(checksums.encode("utf-8")))

	def __del__(self):
		print("Socket Delete")

	def onDisconnect(self):
		RemoteClient._disconnect_()

	def onRead(self):
		# [py3/PySide6] QIODevice.read() 는 QByteArray 를 돌려준다.
		# 예전 코드는 이걸 str() 로 감쌌는데, PySide(Qt4) 에서는 내용이 나왔지만 PySide6 는
		# repr 을 준다 (b'PATH'). 그래서 아래 len(order) == 4 검사가 항상 실패하면서
		# 엔진에서 PATH 를 받은 뒤 파일 전송이 통째로 멈춰 있었다.
		# 4문자 opcode 는 str 로, 페이로드는 bytes 로 다룬다.
		fin = QDataStream(self)
		print("<<<<<<Recived")
		if self.order == None:
			if self.bytesAvailable() >= 4 :
				self.order = bytes(fin.device().read(4)).decode("ascii", "replace")
				self.payloadSize = -1
				print("ordered << ",self.order)

		print("____0")
		if self.order != None and self.payloadSize == -1 and len(self.order) == 4 :
			if self.bytesAvailable() >= 11 :
				# 길이 필드는 공백으로 11바이트까지 채워진 10진수 문자열이다.
				self.payloadSize = int(bytes(fin.device().read(11)).decode("ascii").strip())
				self.payload = b""
				print("size << ",self.payloadSize)

		print("____1")
		if self.order != None and self.payloadSize != -1 and self.payloadSize != None :
			availBytes = self.bytesAvailable()

			print("____2",availBytes,self.payloadSize)

			if availBytes > 0 and availBytes < self.payloadSize :
				self.payload += bytes(fin.device().read(availBytes))
				self.payloadSize -= availBytes
				availBytes = self.bytesAvailable()

			if availBytes >= self.payloadSize :
				print("____3")
				self.payload += bytes(fin.device().read(self.payloadSize))
				self.payloadSize = 0
				print("____4")

		print("____5")
		if self.order != None and self.payloadSize == 0 and self.payload != None : 
			print("____6")
			self.OnRecved(self.order,self.payloadSize,self.payload)
			print("____7")
			self.order = None
			self.payloadSize = None
			self.payload = None

	def send(self,order,payload):
		if self.live :
			# PySide6 의 QByteArray 는 str 을 받지 않는다 (bytes 여야 한다).
			header=QByteArray(order.encode("ascii"))
			header.resize(4)

			s_size = str(payload.size())
			size=QByteArray((s_size+" "*(11-len(s_size))).encode("ascii"))

			#print ">>>>>>>>>>>>>>>>>>>>>>>"
			print("\"",header,"\"",self.write(header))
			print("\"",size,"\"",self.write(size))
			print("payload",self.write(payload))

			OutputWindow().notice("리모트 데이터 전송:"+order+" ["+str(payload.size())+"]")

	def sendFile(self,fpath,dist,fname):
		if self.live : 
			fp = QFile( fpath )
			fp.open( QFile.ReadOnly )
			fbyte = fp.readAll()
			fp.close()

			byte = QByteArray()

			dist = dist.replace("\\","/")

			s1 = QByteArray.number(len(dist))
			s1.resize(4)

			dist = QByteArray(dist.encode("utf-8"))

			s2 = QByteArray.number(len(fname))
			s2.resize(4)

			fname = QByteArray(fname.encode("utf-8"))

			byte.append(s1)
			byte.append(dist)
			byte.append(s2)
			byte.append(fname)
			byte.append(fbyte)

			self.send("tran",byte)
			OutputWindow().notice("파일 전송:"+fpath)

	@staticmethod
	def _disconnect_():
		if RemoteClient._instance:
			RemoteClient._instance.status = 0
			RemoteClient._instance.live = False
			RemoteClient._instance.close()

			RemoteClient._isInit = False
			RemoteClient._instance = None
