
from PySide6.QtCore import *
from PySide6.QtGui import *
from PySide6.QtWidgets import *

import shutil
import os
from PIL import Image

class FontManager(object) : 
	_instance = None
	_isInit   = False
	def __new__(cls, *args, **kwargs):
		if not FontManager._instance:
			FontManager._instance = super(FontManager,cls).__new__(cls,*args,**kwargs)

		return FontManager._instance

	def __init__(self,src=None,parent=None):
		if FontManager._isInit:
			return 
		FontManager._isInit = True

		super(FontManager,self).__init__()

		self.fonts = {}
		self.reset()

	def reset(self):
		QFontDatabase.removeAllApplicationFonts()
		self.fonts = {}

		self.AddFont("NanumBarunGothic","resource/NanumBarunGothic.ttf")
		self.AddFont("NanumGothicCoding","resource/NanumGothicCoding.ttf")

	def AddFont(self,idx,path):
		if idx in self.fonts : 
			return

		# Qt6 의 addApplicationFont 는 상대 경로를 열지 못하고 -1 을 돌려준다.
		# (Qt4 에서는 cwd 기준 상대 경로가 통했다.) 절대 경로로 바꿔서 넘긴다.
		_id = QFontDatabase.addApplicationFont(os.path.abspath(path))
		families = QFontDatabase.applicationFontFamilies(_id)
		if not families :
			print("폰트를 불러오지 못했습니다:",path)
			return None
		family = families[0]

		self.fonts[idx] = family

		return family

	def FontName(self,idx):
		if idx in self.fonts : 
			return self.fonts[idx]
		else:
			for k,v in self.fonts.items():
				return v
			return ""