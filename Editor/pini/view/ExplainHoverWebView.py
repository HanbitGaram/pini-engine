# -*- coding: utf-8 -*-
import sys

from PySide6.QtGui import *
from PySide6.QtWidgets import *
from PySide6.QtCore import *

from view.ExplainWebView import ExplainBrowserBase


class ExplainHoverWebView(ExplainBrowserBase):
	# 마우스를 글자에 두었을때 뜨는 툴팁창
	# (QtWebKit -> QTextBrowser 대체. 사유는 ExplainBrowserBase 주석 참조)
	def __init__(self, parent=None):
		super(ExplainHoverWebView, self).__init__(parent)

	def leaveEvent(self, e):
		self.resize(0, 0)
		return super(ExplainHoverWebView, self).leaveEvent(e)
