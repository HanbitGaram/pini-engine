# -*- coding: utf-8 -*-
import sys

from PySide6.QtGui import *
from PySide6.QtWidgets import *
from PySide6.QtCore import *
from Noriter.views.NoriterMainWindow import *
from Noriter.utils.Settings import Settings
from controller.ProjectController import ProjectController

import os
import json
import urllib.request, urllib.error, urllib.parse
import locale

class UpdatorUpdateThread(QThread):
	def run(self):
		#check exist updator
		if os.path.isfile("../_pygit2.pyd") : 
			try:
				distURL = "http://nooslab.com/piniengine/updator_latest/"
				req = urllib.request.Request(url=distURL+'version.inf')
				f = urllib.request.urlopen(req)

				serverVer = int(f.read())
				localVer = -1

				updateVerInf = "../update_ver.inf"
				if os.path.isfile(updateVerInf) : 
					f = open(updateVerInf,"r")
					localVer = int(f.read())
					f.close()
				
				f = open(updateVerInf,"w")
				f.write(str(serverVer))
				f.close()

				if serverVer > localVer : 
					import wget

					url = distURL+'Updator.exe'
					filename = wget.download(url)

					try:
						os.remove("../피니엔진.exe")
					except Exception as e:
						sys.stderr.write( str(e) )
						sys.stderr.write( "\n" )

					try:
						os.rename(filename,"../피니엔진.exe")
					except Exception as e:
						sys.stderr.write( str(e) )
						sys.stderr.write( "\n" )

			except Exception as e:
				sys.stderr.write( str(e) )

class LoaderWindow(QLabel):
	def __init__(self,parent=None):
		super(LoaderWindow,self).__init__(parent)
		rec = QApplication.primaryScreen().geometry();  # Qt6: QApplication.desktop() 제거됨
		height = rec.height();
		width = rec.width();

		img = QPixmap("resource/splash/pini.png")

		self.setPixmap(img)
		self.setWindowFlags(Qt.FramelessWindowHint)
		self.move(width/2 - img.rect().width()/2,height/2 - img.rect().height()/2)
		self.setScaledContents(True)
		self.show()

		layout = QHBoxLayout()
		layout.setContentsMargins(0,417,0,0)
		self.setLayout(layout)

		self.progress = QProgressBar(self)
		layout.addWidget(self.progress)

		self.step_func = [self.step1, self.step2, 
						 self.step3_1, self.step3_2, self.step3_3, self.step3_4,
						 self.step3, self.step4,
						 self.step5, self.step6, self.step7, self.step8,
						 self.step9, self.step10, self.step11, self.step12]


		self.stepIdx = 0
		QTimer.singleShot(20,self.updateStep)

	def updateStep(self):
		if self.stepIdx >= len(self.step_func) : 
			return

		self.step_func[self.stepIdx]()

		self.stepIdx += 1
		self.progress.setValue(float(self.stepIdx) / len(self.step_func) * 100 )
		QTimer.singleShot(100,self.updateStep)

	def step1(self):
		css = QFile( "resource/QMain.css" )
		css.open( QFile.ReadOnly )

		styleSheet = css.readAll()
		# PySide(Qt4) 에서는 str(QByteArray) 가 내용을 돌려줬지만 PySide6 에서는 repr
		# (예: b'QToolTip\n{...') 이 나온다. 그대로 넘기면 Qt 가 스타일시트를 파싱하지
		# 못해 ("Could not parse application stylesheet") 테마가 통째로 적용되지 않는다.
		QApplication.instance().setStyleSheet(styleSheet.data().decode("utf-8"))

		css.close()

	def step2(self):
		m = NoriterMain()
		m.hide()
		m.resize(1200,600)
		m.move(50,50)
		m.setTabPosition(Qt.AllDockWidgetAreas,QTabWidget.North)

	def step3(self):
		print ("step3_f ready")
		from view.Launcher import LauncherView
		print ("step3_f done")

	def step3_1(self):
		print ("step3_1 ready")
		from PySide6 import QtGui,QtCore,QtWidgets
		from Noriter.UI.ModalWindow import ModalWindow 
		from Noriter.UI.Window import Window 
		from Noriter.UI.Widget import Widget 
		print ("step3_1 done")

	def step3_2(self):
		print ("step3_2 ready")
		from Noriter.utils.Settings import Settings
		print ("step3_2 done")

	def step3_3(self):
		print ("step3_3 ready")
		from controller.ProjectController import ProjectController
		from command.ScriptCommands import ScriptGraphicsProtocol
		print ("step3_3 done")

	def step3_4(self):
		print ("step3_4 ready")
		import shutil
		import glob
		import locale
		print ("step3_4 done")

	def step4(self):
		from view.SceneDocument import SceneDocument
		from view.AssetLibraryWindow import AssetLibraryWindow

	def step5(self):
		from view.OutputWindow import OutputWindow
		from view.VariableViewWindow import VariableViewWindow

	def step6(self):
		from view import Menu
		from controller.SceneListController import SceneListController

	def step7(self):
		from view.OutputWindow import OutputWindow
		from view.VariableViewWindow import VariableViewWindow
		m = NoriterMain()
		##### VIEWS!! ######
		OutputWindow(m).hide()
		VariableViewWindow().hide()

	def step8(self):
		from view.SceneDocument import SceneDocument
		m = NoriterMain()
		m.SetMain(SceneDocument(m))

	def step9(self):
		print("step9_0")
		from view.SceneScriptWindow import SceneScriptWindowManager
		# print "step9_1"
		m = NoriterMain()
		m.setWindowIcon(QIcon('resource/logoIcon64.png')) 
		# print "step9_2"
		# self.bb = SceneScriptWindow(m)
		print("step9_3")
		SceneScriptWindowManager()
	
	def step10(self):
		# m = NoriterMain()
		# m.Dock(NoriterMain.DOCK_RIGHT,self.bb,False)
		pass

	def step11(self):
		from view.AssetLibraryWindow import AssetLibraryWindow
		m = NoriterMain()
		m.Dock(NoriterMain.DOCK_BOTTOM,AssetLibraryWindow(m),False)
		m.statusBar().showMessage("Ready")

	def step12(self):
		from view.Launcher import LauncherView
		# Qt6 에서는 '부모가 있는 창' 이 quitOnLastWindowClosed 계산에 포함되지 않는다.
		# 런처를 NoriterMain 의 자식으로 만들면, 스플래시가 닫히고 메인 창이 숨겨지는 순간
		# Qt 가 "마지막 창이 닫혔다" 고 보고 앱을 그대로 종료해 버린다 (Qt4 에서는 아니었다).
		# 부모 없는 독립 창으로 만들고, 파이썬 참조만 붙들어 GC 를 막는다.
		m = NoriterMain()
		launcher = LauncherView(None)
		m.launcher = launcher
		self.close()
		
		m.hide()

		def fileOpen(fileName):
			fp = QFile(fileName)
			fp.open(QIODevice.ReadOnly | QIODevice.Text)

			fin = QTextStream(fp)
			fin.setEncoding(QStringConverter.Utf8)
			FILEDATA = fin.readAll()
			fin = None
			fp.close()

			return FILEDATA

		def PJOIN(*paths):
			# py2 에서는 각 조각을 로케일 인코딩 bytes 로 바꿔 os 에 넘기고 경로 구분자를
			# 윈도우식 백슬래시로 강제했다. py3 는 경로를 str 로 다루고, mac/리눅스에서는
			# 백슬래시가 구분자가 아니므로 os.sep 으로 맞춘다 (윈도우에서는 결과가 동일).
			parts = [str(v).replace("\\", "/") for v in paths]
			return os.path.join(*parts).replace("/", os.sep)

		tmp_path_master = PJOIN(".","tempSave","PROJ")
		if os.path.exists(tmp_path_master):
			from controller.SceneListController import SceneListController
			from view.SceneScriptWindow import SceneScriptWindowManager

			DAT = json.loads(fileOpen(tmp_path_master))

			if not os.path.exists(DAT["PROJ"]):
				print("NO BACKUP PROJECT FOUND")
				return

			launcher.close()

			ProjectController().path = DAT["PROJ"]
			PROJPATH = DAT["PROJ"]

			QMessageBox.warning(self,"피니엔진","저장되지 않은 파일이 감지되었습니다. 임시파일을 불러옵니다.")
			NoriterMain().show()

			for root, dirs, files in os.walk(PJOIN(".","tempSave"), topdown=False):
				for backupFileName in files:
					if backupFileName != "PROJ":
						BACK = json.loads(fileOpen(PJOIN(".","tempSave",backupFileName)))
						targetFileName = backupFileName.replace("__!_","/").replace(".tmp",".lnx")
						relativePath = "scene/"+targetFileName
						SceneListController.getInstance().Open(PROJPATH+"/scene/"+targetFileName)

						SceneScriptWindowManager.getInstance().windows[relativePath].editor.setPlainText(BACK["PLAIN"])
						SceneScriptWindowManager.getInstance().windows[relativePath].editor.compileAll()
						SceneScriptWindowManager.getInstance().windows[relativePath].editor.commitGraphics()

		def _Update_Updator_():
			updateThread = UpdatorUpdateThread(NoriterMain())
			updateThread.start()

		QTimer.singleShot(1500,_Update_Updator_)