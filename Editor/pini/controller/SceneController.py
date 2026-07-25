# -*- coding: utf-8 -*-
import sys

import os
import json

from PySide6.QtCore import *
from PySide6.QtGui import *
from PySide6.QtWidgets import *

class SceneController(QObject):
	def __init__(self):
		super(SceneController,self).__init__()
		self.path = ""
		self.view = None
		self.needSave = False
		
	def Load(self,path):
		self.path = path
		fp = QFile(path)
		fp.open(QIODevice.ReadOnly | QIODevice.Text)

		fin = QTextStream(fp)
		fin.setEncoding(QStringConverter.Utf8)

		self.plainText = fin.readAll()

		fin = None
		fp.close()

	def Save(self,plainText):
		fp = QFile(self.path)
		print(("Save..." + self.path))
		fp.open(QIODevice.WriteOnly | QIODevice.Text)
		
		out = QTextStream(fp)
		out.setEncoding(QStringConverter.Utf8)
		out.setGenerateByteOrderMark(False)
		out<<plainText
		out = None
		fp.close()

		self.needSave = False

