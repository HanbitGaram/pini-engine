# -*- coding: utf-8 -*-

from PySide6.QtGui import *
from PySide6.QtWidgets import *
from PySide6.QtCore import *
from controller.ProjectController import *

import shutil
import copy
import json

class Utils:
	@staticmethod
	def ContextMenu(arr,parent):
		menu = QMenu(parent.tr(arr[0]), parent);
		for c in arr[1:] : 
			if isinstance(c, list) :
				menu.addMenu(QtUtils.ContextMenu(c,parent));
			elif isinstance(c , str):
				menu.addAction(QAction(parent.tr(c), parent));
			else:
				menu.addSeparator();
		return menu

	@staticmethod
	def GetResourcePath(_parent,_filter=''):
		pc = ProjectController.getInstance()
		fileName,filt = QFileDialog.getOpenFileName(parent = _parent,dir = pc.path,filter=_filter)
		if len(fileName) > 0:
			if pc.path in fileName:
				return fileName.replace(pc.path,str(''))
			else:
				q = QMessageBox.question(_parent,_parent.tr("파일 복사"),_parent.tr("해당 파일을 프로젝트 폴더에 복사하시겠습니까?"),QMessageBox.Cancel,QMessageBox.Yes)
				if q == QMessageBox.Yes :
					fi = QFileInfo(fileName)
					destPath = os.path.join(pc.path,fi.fileName())

					shutil.copyfile(fileName,destPath)

					return os.sep + fi.fileName()
				return ''

