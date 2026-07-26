# -*- coding: utf-8 -*-
#
# iOS 익스포트.
#
# Export_Windows / Export_Android 와 달리 도구 호출을 파이썬 안에 박지 않고
# scripts/export-ios.sh 에 위임한다. 그 둘이 windows 도구체인(luac.exe, 7z.exe,
# jarsigner.exe ...)에 묶여 mac 에서 못 쓰게 된 전철을 밟지 않기 위해서다.
# 여기서 하는 일은 (1) 게임 리소스 스테이징, (2) 스크립트 실행과 로그 표시뿐이다.
import os
import re
import shutil
import subprocess

from PySide6.QtGui import *
from PySide6.QtWidgets import *
from PySide6.QtCore import *

from Noriter.UI.ModalWindow import ModalWindow
from Noriter.utils.Settings import Settings
from Noriter.views.NoriterMainWindow import *

from controller.ProjectController import ProjectController
from view.AssetLibraryWindow import AssetLibraryWindow

from config import *


# 에디터는 Editor/pini 에서 실행된다 (Export_Windows 의 "../../Engine/..." 과 같은 기준).
REPO_ROOT = os.path.abspath(os.path.join("..", ".."))
ENGINE_DIR = os.path.join(REPO_ROOT, "Engine", "VisNovel")
IOS_PROJ_DIR = os.path.join(ENGINE_DIR, "frameworks", "runtime-src", "proj.ios_mac")
EXPORT_SCRIPT = os.path.join(REPO_ROOT, "scripts", "export-ios.sh")

# 애플이 요구하는 번들 식별자 형식. 여기서 걸러 주지 않으면 20분짜리 아카이브가
# 끝난 뒤에야 xcodebuild 가 거부한다.
BUNDLE_ID_RE = re.compile(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$")

EXPORT_METHODS = [
	("개발용 (등록된 기기에만 설치)", "development"),
	("Ad Hoc (등록된 기기 배포)", "ad-hoc"),
	("App Store Connect 업로드용", "app-store"),
	("사내 배포 (Enterprise)", "enterprise"),
]


class ExportThread(QThread):
	"""scripts/export-ios.sh 를 돌리면서 출력을 실시간으로 흘려보낸다.

	아카이브는 몇 분에서 수십 분까지 걸린다. 진행 상황이 안 보이면 멈춘 것과
	구분이 안 되므로 로그를 그대로 보여 준다."""

	# ModalWindow 는 QDialog 라서 finished/done/thread 라는 이름이 이미 Qt 것이다.
	# 그 이름을 그대로 쓰면 시그널이나 메서드가 조용히 가려진다 (실제로 self.finished 가
	# QDialog.finished(int) 로 잡혀 connect 가 실패했다). 접두어를 붙여 피한다.
	logLine = Signal(str)
	exportDone = Signal(bool, str)

	def __init__(self, env, parent=None):
		super(ExportThread, self).__init__(parent)
		self.env = env
		self._proc = None

	def run(self):
		env = dict(os.environ)
		env.update(self.env)
		tail = ""
		try:
			self._proc = subprocess.Popen(
				["/bin/bash", EXPORT_SCRIPT],
				cwd=REPO_ROOT,
				stdout=subprocess.PIPE,
				stderr=subprocess.STDOUT,
				env=env,
			)
			for raw in iter(self._proc.stdout.readline, b""):
				text = raw.decode("utf-8", "replace").rstrip()
				tail = text or tail
				self.logLine.emit(text)
			self._proc.stdout.close()
			code = self._proc.wait()
		except Exception as e:
			self.exportDone.emit(False, str(e))
			return

		self.exportDone.emit(code == 0, tail)

	def stop(self):
		if self._proc and self._proc.poll() is None:
			self._proc.terminate()


class ExportIOSWindow(ModalWindow):
	def sizeHint(self):
		return QSize(430, 0)

	def __init__(self, src=None, parent=None):
		self.export_thread = None
		self.result_path = ""
		self.icon_path = ""
		super(ExportIOSWindow, self).__init__(parent)
		self.setWindowTitle("iOS 익스포트")

	def closeEvent(self, e):
		# 실행 중인 xcodebuild 를 두고 창만 닫히면 좀비 프로세스가 남는다.
		if self.export_thread and self.export_thread.isRunning():
			self.export_thread.stop()
			self.export_thread.wait(3000)
		super(ExportIOSWindow, self).closeEvent(e)

	# ------------------------------------------------------------------ 환경 점검

	def check_environment(self):
		"""익스포트가 가능한 상태인지 본다. 문제가 있으면 사람이 읽을 수 있는 사유를 돌려준다."""
		if not os.path.isdir(IOS_PROJ_DIR):
			return ("iOS 프로젝트를 찾을 수 없습니다.\n%s\n\n"
			        "iOS 익스포트는 엔진 소스가 함께 있는 개발용 배치에서만 됩니다." % IOS_PROJ_DIR)
		if not os.path.isfile(EXPORT_SCRIPT):
			return "익스포트 스크립트가 없습니다.\n%s" % EXPORT_SCRIPT
		try:
			subprocess.check_output(["xcodebuild", "-version"], stderr=subprocess.STDOUT)
		except Exception:
			return ("Xcode 를 찾을 수 없습니다.\n\n"
			        "App Store 에서 Xcode 를 설치한 뒤 터미널에서\n"
			        "    sudo xcode-select --switch /Applications/Xcode.app\n"
			        "를 실행해 주세요.")
		return None

	# ------------------------------------------------------------------ 스테이징

	def stage_resources(self, stagedir, gamename):
		"""번들에 들어갈 src/res 를 만든다.

		순서는 Export_Windows 와 같다. 프로젝트 컴파일 결과를 먼저 깔고 그 위에
		엔진 기본 src/res 를 덮는다 (엔진 쪽이 우선)."""
		inst = ProjectController()
		buildpath = os.path.join(inst.path, "build")
		srcpath = os.path.join(stagedir, "src")
		respath = os.path.join(stagedir, "res")

		if os.path.isdir(stagedir):
			shutil.rmtree(stagedir)
		os.makedirs(srcpath)
		os.makedirs(respath)

		def copy_tree(source, dist):
			if not os.path.isdir(source):
				return
			for root, dirs, files in os.walk(source):
				for name in files:
					path = os.path.join(root, name)
					# .obj 는 컴파일 중간 산출물이라 뺀다 (Export_Windows 와 동일).
					if os.path.splitext(name)[1] == ".obj":
						continue
					target = os.path.join(dist, os.path.relpath(path, source))
					if not os.path.isdir(os.path.dirname(target)):
						os.makedirs(os.path.dirname(target))
					shutil.copyfile(path, target)

		copy_tree(buildpath, srcpath)
		copy_tree(os.path.join(ENGINE_DIR, "src"), srcpath)
		copy_tree(os.path.join(ENGINE_DIR, "res"), respath)

		# 엔진이 어느 게임을 띄울지 알려 주는 파일. 이게 없으면 런타임이 원격 모드로 뜬다.
		with open(os.path.join(srcpath, "_export_execute_.lua"), "w", encoding="utf-8") as f:
			f.write('return "%s"' % gamename)

		return stagedir

	# ------------------------------------------------------------------ 실행

	def btn_find_dist_path(self):
		path = QFileDialog.getExistingDirectory(parent=self, caption="저장할 위치")
		if path:
			self.savePath.setText(path)

	def find_icon(self):
		path, _ = QFileDialog.getOpenFileName(
			parent=self, caption="앱 아이콘", filter="이미지 (*.png *.jpg *.jpeg)")
		if not path:
			return
		inst = ProjectController()
		with Settings("IOS_EXPORT"):
			with Settings(inst.path):
				Settings()["iconpath"] = path
		self.icon_path = path
		self.appIcon.setPixmap(QPixmap(path).scaled(
			60, 60, Qt.KeepAspectRatio, Qt.SmoothTransformation))

	def open_export_dir(self):
		QDesktopServices.openUrl(QUrl.fromLocalFile(self.result_path))

	def export(self):
		savepath = self.savePath.text().strip()
		gamename = self.saveGameName.text().strip()
		bundleid = self.saveBundleId.text().strip()
		version = self.saveVersion.text().strip()
		build_no = self.saveBuildNo.text().strip()
		team_id = self.saveTeamId.text().strip()
		method = EXPORT_METHODS[self.saveMethod.currentIndex()][1]

		if not savepath:
			QMessageBox.warning(self, "Pini", "저장 위치를 지정해주세요!")
			return
		if not gamename:
			QMessageBox.warning(self, "Pini", "게임명을 정해주세요!")
			return
		if not BUNDLE_ID_RE.match(bundleid):
			QMessageBox.warning(self, "Pini",
			                    "번들 ID 형식이 올바르지 않습니다.\n"
			                    "예: com.회사이름.게임이름\n\n"
			                    "영문/숫자/하이픈과 점만 쓸 수 있고, 점이 최소 하나 있어야 합니다.")
			return
		if not team_id:
			ret = QMessageBox.question(
				self, "Pini",
				"Apple 팀 ID 가 없으면 서명을 못 해서 기기에 설치할 수 없는\n"
				"아카이브(.xcarchive)까지만 만들어집니다.\n\n계속할까요?",
				QMessageBox.Yes | QMessageBox.No)
			if ret != QMessageBox.Yes:
				return

		inst = ProjectController()
		with Settings("IOS_EXPORT"):
			with Settings(inst.path):
				Settings()["path"] = savepath
				Settings()["game"] = gamename
				Settings()["bundleid"] = bundleid
				Settings()["version"] = version
				Settings()["build"] = build_no
				Settings()["team"] = team_id
				Settings()["method"] = method

		outdir = os.path.join(savepath, "export_ios")
		stagedir = os.path.join(outdir, "stage")

		# 에셋 감시자가 켜져 있으면 스테이징 중 파일 이동에 반응해서 느려지고 오작동한다.
		AssetLibraryWindow().watcherOn = False
		AssetLibraryWindow().watcher = None

		self.GUI_PROGRESS()
		self.log("프로젝트 컴파일 중...")

		def after_compile(arg1, arg2):
			try:
				self.log("리소스 스테이징: %s" % stagedir)
				self.stage_resources(stagedir, gamename)
			except Exception as e:
				self.on_export_done(False, "스테이징 실패: %s" % e)
				return

			self.log("Xcode 아카이브 시작 — 수 분 걸릴 수 있습니다.")
			env = {
				"STAGE": stagedir,
				"OUTDIR": outdir,
				"APP_NAME": gamename,
				"BUNDLE_ID": bundleid,
				"VERSION": version or "1.0",
				"BUILD_NUMBER": build_no or "1",
				"TEAM_ID": team_id,
				"METHOD": method,
			}
			if self.icon_path and os.path.isfile(self.icon_path):
				env["ICON"] = self.icon_path
			self.result_path = outdir
			self.export_thread = ExportThread(env, self)
			self.export_thread.logLine.connect(self.log)
			self.export_thread.exportDone.connect(self.on_export_done)
			self.export_thread.start()

		inst.compileProj(False, after_compile)

	def log(self, text):
		self.logview.appendPlainText(text)
		bar = self.logview.verticalScrollBar()
		bar.setValue(bar.maximum())

	def on_export_done(self, ok, tail):
		AssetLibraryWindow().watcherOn = True
		AssetLibraryWindow().updateWatcher()

		if ok:
			self.log("\n완료: %s" % tail)
			self.GUI_FIN_EXPORT()
		else:
			self.log("\n실패: %s" % tail)
			QMessageBox.warning(self, "Pini",
			                    "익스포트에 실패했습니다.\n아래 로그의 마지막 오류를 확인해주세요.\n\n%s" % tail)

	# ------------------------------------------------------------------ GUI

	@LayoutGUI
	def GUI(self):
		problem = self.check_environment()
		if problem:
			self.Layout.clear()
			self.Layout.label("<b>iOS 익스포트를 할 수 없습니다</b>")
			self.Layout.hline()
			self.Layout.gap(3)
			self.Layout.label(problem.replace("\n", "<br>"))
			self.Layout.gap(3)
			self.Layout.button("닫기", self.close)
			self.resize(430, 0)
			return

		savepath = ""
		gamename = "테스트게임"
		bundleid = "com.example.pinigame"
		version = "1.0"
		build_no = "1"
		team_id = ""
		method = "development"
		iconpath = "resource/export_default_icon.png"

		inst = ProjectController()
		with Settings("IOS_EXPORT"):
			with Settings(inst.path):
				savepath = Settings()["path"] or savepath
				gamename = Settings()["game"] or gamename
				bundleid = Settings()["bundleid"] or bundleid
				version = Settings()["version"] or version
				build_no = Settings()["build"] or build_no
				team_id = Settings()["team"] or team_id
				method = Settings()["method"] or method
				iconpath = Settings()["iconpath"] or iconpath

		self.Layout.clear()
		self.icon_path = iconpath if os.path.isfile(iconpath) else ""

		self.Layout.label("<b>1. 앱 정보 설정</b>")
		self.Layout.hline()
		self.Layout.gap(3)

		with Layout.HBox():
			with Layout.VBox():
				with Layout.HBox():
					self.Layout.label("저장위치").setFixedWidth(90)
					self.savePath = self.Layout.input(savepath, None)
					self.Layout.button("...", self.btn_find_dist_path).setFixedHeight(20)
				with Layout.HBox():
					self.Layout.label("게임명").setFixedWidth(90)
					self.saveGameName = self.Layout.input(gamename, None)
				with Layout.HBox():
					self.Layout.label("번들 ID").setFixedWidth(90)
					self.saveBundleId = self.Layout.input(bundleid, None)
				with Layout.HBox():
					self.Layout.label("버전").setFixedWidth(90)
					self.saveVersion = self.Layout.input(version, None)
				with Layout.HBox():
					self.Layout.label("빌드번호").setFixedWidth(90)
					self.saveBuildNo = self.Layout.input(build_no, None)
				with Layout.HBox():
					self.Layout.label("Apple 팀 ID").setFixedWidth(90)
					self.saveTeamId = self.Layout.input(team_id, None)
				with Layout.HBox():
					self.Layout.label("배포 방식").setFixedWidth(90)
					self.saveMethod = self.Layout.combo([v[0] for v in EXPORT_METHODS])
				self.Layout.spacer()

			self.Layout.gap(5)

			with Layout.VBox():
				self.appIcon = self.Layout.img(iconpath)
				self.appIcon.setFixedSize(60, 60)
				self.Layout.button("...", self.find_icon).setFixedHeight(20)
				self.Layout.spacer()

		names = [v[1] for v in EXPORT_METHODS]
		if method in names:
			self.saveMethod.setCurrentIndex(names.index(method))

		self.Layout.gap(3)
		self.Layout.label(
			"<small>팀 ID 는 developer.apple.com 의 Membership 에서 확인할 수 있는 "
			"10자리 문자열입니다.<br>"
			"실기기 설치와 스토어 제출에는 Apple Developer Program 가입이 필요합니다.</small>")
		self.Layout.gap(2)
		self.Layout.hline()
		self.Layout.gap(2)
		self.Layout.button("익스포트", self.export)
		self.resize(430, 0)

	@LayoutGUI
	def GUI_PROGRESS(self):
		self.Layout.clear()
		self.Layout.label("<b>2. 익스포트 진행 중</b>")
		self.Layout.hline()
		self.Layout.gap(3)

		self.logview = QPlainTextEdit()
		self.logview.setReadOnly(True)
		self.logview.setMaximumBlockCount(5000)
		self.logview.setLineWrapMode(QPlainTextEdit.NoWrap)
		self.Layout.addWidget(self.logview)

		self.Layout.gap(2)
		self.Layout.button("취소", self.close)
		self.resize(700, 460)

	@LayoutGUI
	def GUI_FIN_EXPORT(self):
		self.Layout.clear()
		self.Layout.label("<b>3. 익스포트 완료</b>")
		self.Layout.hline()
		self.Layout.gap(3)

		with Layout.HBox():
			self.Layout.label(self.result_path)
			self.Layout.button("열기", self.open_export_dir).setFixedSize(50, 20)

		self.Layout.gap(3)
		self.Layout.label(
			"<small>.ipa 는 Apple Configurator 나 Xcode 의 Devices 창으로 기기에 설치할 수 있습니다.<br>"
			"App Store 제출용은 Transporter 앱으로 업로드하세요.</small>")
		self.Layout.spacer()
		self.Layout.hline()
		self.Layout.button("익스포트 종료", self.close)
		self.resize(560, 240)
