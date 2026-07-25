# -*- coding: utf-8 -*-
import sys

from PySide6.QtGui import *
from PySide6.QtWidgets import *
from PySide6.QtCore import *


class ExplainBrowserBase(QTextBrowser):
	"""QtWebKit(QWebView) 대체용 공통 베이스.

	QtWebKit 은 Qt5.6 에서 제거되어 Qt6/PySide6 에는 없다. 이 위젯들이 하던 일은
	'도움말 HTML 조각을 보여주고 링크를 누르면 외부 브라우저로 연다' 뿐이라
	무거운 QtWebEngine 대신 QTextBrowser 로 충분하다.
	"""

	def __init__(self, parent=None):
		super(ExplainBrowserBase, self).__init__(parent)

		# QTextBrowser 는 기본적으로 링크를 자기 안에서 연다. 예전 QWebView 동작
		# (setLinkDelegationPolicy(DelegateAllLinks) + linkClicked) 과 맞추려고 끈다.
		self.setOpenLinks(False)
		self.anchorClicked.connect(self.onLinkClicked)

		# 예전에는 settings().setUserStyleSheetUrl(...) 로 걸던 스타일시트를
		# QTextDocument 의 기본 스타일시트로 적용한다.
		try:
			with open("resource/explain.css", encoding="utf-8") as fp:
				self.document().setDefaultStyleSheet(fp.read())
		except OSError:
			pass

	def onLinkClicked(self, url):
		QDesktopServices.openUrl(url)

	def hideEvent(self, e):
		self.clearFocus()
		return super(ExplainBrowserBase, self).hideEvent(e)


class ExplainWebView(ExplainBrowserBase):
	# 자동완성과 같이 뜨는 툴팁창
	def __init__(self, completer, parent=None):
		super(ExplainWebView, self).__init__(parent)
		self.completer = completer
