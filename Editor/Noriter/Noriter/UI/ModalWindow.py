from PySide6 import QtCore,QtGui,QtWidgets

from Noriter.UI.Layout import *
from Noriter.UI import NoriterWindow as nWin

class ModalWindow(nWin.NoriterWindow, QtWidgets.QDialog):
	def __init__(self,parent):
		super(ModalWindow, self).__init__(parent)

		QtCore.QMetaObject.connectSlotsByName(self)
		self.setWindowModality(QtCore.Qt.ApplicationModal)
		
	@LayoutGUI
	def GUI(self):
		pass
