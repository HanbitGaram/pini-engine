# -*- coding: utf-8 -*-
import sys

from PySide6 import QtGui,QtCore,QtWidgets
from Noriter.UI.ModalWindow import ModalWindow 
from Noriter.UI.Window import Window 
from Noriter.utils.Settings import Settings
from Noriter.views.NoriterMainWindow import *

from controller.ProjectController import ProjectController

class AboutPiniWindow(ModalWindow):
	def __init__(self,parent):
		super(AboutPiniWindow,self).__init__(parent)

		self._layout.setContentsMargins(5, 5, 5, 5)
		self._layout.setSpacing(4)

		self.modify = False

	@LayoutGUI
	def GUI(self):
		self.Layout.label(self.tr("<b>피니엔진 오픈소스 버전</b>"))

		compilerVersion = ""
		try:
			# pini_ver.inf 는 업데이터(Editor/updator)가 만드는 파일이라 소스 체크아웃
			# 에는 없다. open() 은 예외 대신 False 를 주므로 반환값을 봐야 한다.
			# 안 그러면 Qt 가 "device not open" 경고를 찍는다.
			versionDir = os.path.join("..","pini_ver.inf")
			fp = QFile(versionDir)
			if fp.open(QIODevice.ReadOnly | QIODevice.Text):
				fin = QTextStream(fp)
				fin.setEncoding(QStringConverter.Utf8)

				compilerVersion = fin.readAll()

				fin = None
				fp.close()
		except Exception as e:
			pass

		with Layout.HBox(5):
			self.Layout.img("resource/logoIcon64.png").setFixedSize(80,80)

			with Layout.VBox(5):
				self.Layout.label(self.tr("Client version hash : ") + compilerVersion)
				self.Layout.gap(10)
				self.Layout.label(self.tr("Copyrightⓒ 2014-2015 Nooslab"))
				self.Layout.gap(10)
				self.Layout.label(self.tr("이 프로그램은 누구나 자유롭게 사용할 수 있습니다."))
				# self.Layout.gap(10)
				# self.Layout.label(self.tr("Special Thanks To"))
				# self.Layout.label(self.tr("블루"))
				# self.Layout.label(self.tr("하언"))
				# self.Layout.label(self.tr(""))
				# self.Layout.label(self.tr(""))
				pass
				
	def Modified(self):
		self.modify = True
		self.close()

	def exec_(self):
		super(AboutPiniWindow,self).exec_()
		try:
			if self.modify : 
				w = int(self.w.text())
				h = int(self.h.text())
				proCtrl = ProjectController()
				proCtrl.screenWidth = w
				proCtrl.screenHeight = h
				proCtrl.orientation = self.orientation.isChecked()
				#proCtrl.fullscreen = self.fullscreen.isChecked()
		except Exception as e:
			pass
