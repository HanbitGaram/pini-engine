# -*- coding: utf-8 -*-
import sys

from PySide6 import QtGui,QtCore,QtWidgets
from Noriter.UI.ModalWindow import ModalWindow 
from Noriter.UI.Window import Window 
from Noriter.utils.Settings import Settings
from Noriter.views.NoriterMainWindow import *

from controller.ProjectController import ProjectController

class ScreenInfoWindow(ModalWindow):
	def __init__(self,parent):
		super(ScreenInfoWindow,self).__init__(parent)

		self._layout.setContentsMargins(5, 5, 5, 5)
		self._layout.setSpacing(4)

		self.modify = False

	@LayoutGUI
	def GUI(self):
		proCtrl = ProjectController()
		with Layout.HBox(5):
			self.Layout.label(self.tr("너비"))
			self.w = self.Layout.input(str(proCtrl.screenWidth),None)
		
		with Layout.HBox(5):
			self.Layout.label(self.tr("높이"))
			self.h = self.Layout.input(str(proCtrl.screenHeight),None)

		self.fullscreen = self.Layout.checkbox(self.tr("풀스크린"), proCtrl.fullscreen, None)
		self.orientation = self.Layout.checkbox(self.tr("기기 세로 모드"), proCtrl.orientation, None)

		with Layout.HBox(5):
			self.Layout.button(self.tr("수정"),self.Modified)
			self.Layout.button(self.tr("취소"),self.close)

	def Modified(self):
		self.modify = True
		self.close()

	def exec_(self):
		super(ScreenInfoWindow,self).exec_()
		try:
			if self.modify : 
				w = int(self.w.text())
				h = int(self.h.text())
				proCtrl = ProjectController()
				proCtrl.screenWidth = w
				proCtrl.screenHeight = h
				proCtrl.orientation = self.orientation.isChecked()
				proCtrl.fullscreen = self.fullscreen.isChecked()
		except Exception as e:
			pass
