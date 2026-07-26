# PiniEngine 현대화 인수인계 문서

> 작성일: 2026-07-25. 이 문서는 Claude(Fable) 세션에서 수행한 사전 조사 결과와 실행 계획을
> 다른 세션(Opus 등)이 이어받아 작업할 수 있도록 정리한 것이다.
> 목표: **(1) macOS에서 에디터+엔진 구동, (2) iOS 배포, (3) Android 배포.**

## 0. 현재 상태

- 작업 브랜치: `modernize/mac-ios-android`
- **Phase 1 (macOS arm64 네이티브 엔진 빌드) 완료. → 상세는 §9 참조.**
  `scripts/build-deps-apple.sh` + `scripts/build-mac.sh` 두 개로 재현 가능.
- **Phase 2 (에디터 py3 / PySide6 포팅) 완료. → 상세는 §10 참조.**
  `scripts/build-editor-natives.sh` 로 atl.so 를 만든 뒤 `Editor/pini` 에서 `python3 main.py`.
- **Phase 3 (iOS arm64 실기기 빌드) 완료. → 상세는 §11 참조.** `scripts/build-ios.sh`.
- 다음 작업: **Phase 4 (Android)**. §6 Phase 4 참조.
- 로컬 Python 3.13.7 (`/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`)에
  PySide6 6.11.1, lupa 2.8, Pillow, openpyxl, appdirs, ply 설치 완료 (pip 네트워크 사용 가능)
  + cmake 4.4.0 / ninja 1.13 (pip 로 설치, 의존성 빌드에 사용)
- 다음 작업: **Phase 2 (에디터 py3/PySide6 포팅)**. §3.5 순서대로.

## 1. 환경 사실 (검증됨)

| 항목 | 값 |
|---|---|
| 머신 | Apple Silicon (arm64), macOS 15.7.5, Rosetta 2 설치됨 |
| Rosetta 정책 | **의존 금지.** Apple 발표(WWDC25) 기준 Rosetta 2는 macOS 27까지만 일반 지원, macOS 28부터 구형 게임용 일부만 잔존. **최종 산출물은 arm64 네이티브여야 함.** Rosetta는 중간 검증용으로만 허용 |
| Xcode | 26.3 (SDK: macOS 26.2, iOS 26.2) |
| OpenGL.framework | macOS 26.2 SDK에 **아직 존재** (deprecated지만 동작) → cocos2d-x 3.x GL 렌더러 사용 가능 |
| Java | OpenJDK 21 (`/usr/bin/java`) |
| 미설치 | Homebrew, cmake, gradle, ant, Android SDK/NDK (전부 없음) |
| git 기본 브랜치 | master |

## 2. 프로젝트 개요 (검증됨)

- 비주얼 노벨 엔진. 에디터(Python)에서 LNX 스크립트를 PLY로 Lua로 컴파일 → cocos2d-x 런타임(pini_remote)이 실행.
- **cocos2d-x는 3.15.1이 저장소에 통째로 vendored** (`Engine/VisNovel/frameworks/cocos2d-x`). README의 "3.9"는 옛날 정보.
- 주요 디렉토리:
  - `Engine/VisNovel/frameworks/runtime-src/` — C++ 게임 러너. `proj.ios_mac`(Xcode), `proj.android`, `proj.android-studio`, `proj.win32`, `proj.linux`
  - `Engine/VisNovel/src/` — 엔진 Lua 소스 (LXVM.lua, AnimMgr.lua, PiniLib 등)
  - `Engine/OSX.app` — 옛날에 빌드된 mac용 런타임 (에디터가 실행할 때 참조)
  - `Engine/window64/` — Windows용 런타임 바이너리
  - `Editor/pini/` — PySide 에디터 본체, `Editor/Noriter/` — 자체 PySide 위젯 프레임워크
- 에디터 ↔ 엔진 통신: TCP 127.0.0.1:45674, 4문자 opcode 바이너리 프로토콜
  (`PATH`/`flst`/`tran`/`ufin`; 에디터 쪽 `Editor/pini/command/RemoteClient.py`)

## 3. 조사 결과 A — 에디터 (Python) [조사 완료]

포팅 규모: **pini 55파일 15,574줄 + Noriter 25파일 2,243줄 ≈ 17.8k줄.**
`updator/`(1만줄, 대부분 vendored pycparser/pygit2)와 `pini_distribute/`(py2exe 산출물)는 **포팅하지 말고 버릴 것.**

### 3.1 진입점/실행 흐름
- 진입점 `Editor/pini/main.py` (37줄): `reload(sys); sys.setdefaultencoding("utf-8")` (py3에서 제거 필요),
  `../Noriter`를 sys.path에 추가, `Noriter.views.NoriterMainWindow` + `view/LoaderView.LoaderWindow` 구동.
- 엔진 실행: `Editor/pini/view/Menu.py:305-560` `__run__()`.
  - darwin이면 APPPATH = `../../Engine/OSX.app` (dev) → `subprocess.Popen(["open", APPPATH])` (Menu.py:531)
  - **주의(잠재 버그)**: Windows 분기는 실행 전 `window64/src`,`window64/res`를 지우고
    `Engine/VisNovel/src,res`를 복사하는데 **darwin 분기에는 이 리소스 동기화가 없다.**
    mac에서 OSX.app 안의 Resources를 갱신하는 동기화 로직을 추가해야 함.
  - mac의 `open` 호출은 `--fullscreen`/`-workdir` 인자를 전달하지 않음 (`open --args ...`로 고칠 것).
- 컴파일 흐름: `command/CompileThread.py` → `compiler.py`(1,850줄, PLY lex/yacc, LNX→Lua) →
  `<project>/build/` → `appdirs.user_data_dir("pini_remote","")`로 복사 → TCP로 엔진에 전송.

### 3.2 의존성 현황
- PySide import 82곳: QtCore 31, QtGui 27, QtNetwork 4, **QtWebKit 4곳**(ExplainWebView.py,
  ExplainHoverWebView.py, FundingListWindow.py), **phonon 1곳**. → QtWebKit/phonon이 최대 리스크.
  - 권장: QtWebKit → `QTextBrowser` 또는 PySide6 `QtWebEngineWidgets`(무거움) 중 택1.
    도움말 웹뷰 수준이므로 QTextBrowser/외부 브라우저 open으로 대체하는 게 가볍다.
  - phonon → QtMultimedia로 대체 또는 기능 제거.
- PIL 6곳. `pepy/ico_plugin.py`가 `PIL._binary`(현대 Pillow에서 제거됨)를 씀 —
  단, `pepy/`는 Windows PE 아이콘 리라이팅 전용 1,742줄이므로 **mac 포팅에서 제외 가능.**
- lupa: `command/ScriptCommands.py:14,322`에서만 사용. 에디터 내 WYSIWYG 프리뷰가
  엔진과 동일한 Lua 소스(LXVM, AnimMgr, PiniLib, FILEMANS)를 in-process로 실행하는 구조.
  lupa 2.8 (py3.13 wheel)로 동작 가능성 높음.
- `ATL.py:79-80` `cdll.LoadLibrary("ATL.so")` — **ATL.so가 `pini/`에 없음** (fresh checkout에서
  즉시 실패 예상; `pini_distribute/atl.so`는 Windows x86 시절 산출물). 소스는
  `Engine/VisNovel/frameworks/runtime-src/Classes/ATL.cpp`이고 `Engine/ATL_compile.py`가 빌드 스크립트.
  → **arm64 macOS용 ATL.so 재빌드 필요** (clang++ -shared -std=c++11).
  Lua 프리뷰에 FAL_* 콜백 14개를 주입하므로 프리뷰 기능에 필수.
- `nativeUtil/native_compile.py` → `pini/native.so` (BSP 이미지 패킹). 기존 native.so는 아키텍처
  불명이므로 arm64로 재빌드 필요 (`g++ -shared -std=c++11 *.cpp -o ../pini/native.so`를 clang으로).

### 3.3 Windows 전용 코드 (mac에서 분기/제거)
- 실제 `.exe` 참조 47곳: pini_remote.exe(12), jdk.exe, jarsigner.exe, adb.exe, 7z.exe, makensis.exe 등.
  대부분 `view/Export_Windows.py`(775줄), `view/Export_Android.py`(1,226줄)에 집중.
- `_winreg`(Export_Android.py:36), `ctypes.windll`(Export_Windows.py:745-755), `start /w` cmd 문법 12곳.
- `os_encoding.py`: 비-darwin에서 `cdll.kernel32.GetACP()`로 cp949 인코딩 결정, 39곳에서
  `.encode(os_encoding.cp())` 호출. **py3 포팅 시 이 인코딩 모델 전체를 제거하고 str로 통일할 것**
  (2to3가 못 고치는 최대 난관, 모든 파일 경로 코드와 얽혀 있음).
- 이미 darwin 분기 6곳 존재 (Menu.py:433, Export_Windows.py:659, os_encoding.py, GitUpdator.py 등).

### 3.4 Python 2 문법 통계 (pini+Noriter+기타)
- print문 176곳(28파일), `except X, e` 99곳(23파일), `reload` 37곳, `unicode()` 46곳,
  `.iteritems/키류` 16곳, xrange 15곳, `<>` 3곳, basestring 5곳, urllib2 4파일, cStringIO 3파일.
- `u''` 리터럴 441곳은 py3.3+에서 합법이므로 그대로 둬도 됨.
- 주의: **Python 3.13은 2to3/lib2to3가 제거됨.** 자동 변환하려면 별도 도구(예: `pip install
  future`+futurize, 또는 자체 스크립트)를 쓰거나 수작업.
- Qt4→Qt6: PySide6는 비스코프 enum(Qt.AlignLeft)을 아직 허용하므로 enum은 대부분 무수정 통과.
  실제 손 볼 것: `PySide.QtGui` → `PySide6.QtWidgets`+`QtGui` 분리, `exec_()`→`exec()`,
  QRegExp→QRegularExpression, QDesktopWidget→QScreen, setResizeMode→setSectionResizeMode,
  QFontMetrics.width→horizontalAdvance. 대형 파일: `view/ScriptEditor.py`(2,347줄),
  `graphics/GraphicsView.py`(441줄).

### 3.5 에디터 포팅 권장 순서
1. `os_encoding.py`를 no-op(utf-8/str 통일)으로 바꾸고 39개 호출부 정리
2. 기계적 py2→py3 변환 (print/except/xrange/iteritems/urllib2/cStringIO)
3. `PySide` → `PySide6` 임포트 전환 + QtGui/QtWidgets 분리 (Noriter부터 — 2,243줄로 제일 깨끗함)
4. QtWebKit 3파일 → QTextBrowser 대체, phonon 1곳 제거/QtMultimedia
5. ATL.so / native.so arm64 재빌드
6. `QT_QPA_PLATFORM=offscreen python3 main.py`로 스모크 테스트 → 실 GUI 테스트
7. Menu.py darwin 분기에 OSX.app 리소스 동기화 + `open --args` 수정

## 4. 조사 결과 B — 엔진 네이티브 (C++/Xcode) [조사 완료]

경로: `Engine/VisNovel/frameworks/runtime-src/proj.ios_mac/pini_remote.xcodeproj`
(Xcode 3.2 포맷, LastUpgradeCheck 0500)

### 4.1 타겟 구성
| 타겟 | SDK | Deployment | 아키텍처 |
|---|---|---|---|
| `pini_remote-desktop` (mac) | macosx | 10.8 | x86_64 (`ARCHS_STANDARD_64_BIT`) |
| `pini_remote-mobile` (iOS) | iphoneos | **6.0** | `VALID_ARCHS="arm64 armv7"`, bitcode NO |

서브프로젝트 3개 참조 (모두 존재함):
`cocos2d-x/build/cocos2d_libs.xcodeproj`, `cocos/scripting/lua-bindings/proj.ios_mac/cocos2d_lua_bindings.xcodeproj`, `tools/simulator/libsimulator/proj.ios_mac/libsimulator.xcodeproj`

### 4.2 프리빌트 라이브러리 아키텍처 (lipo 검증됨)
- **mac: 전부 x86_64(일부 +i386), arm64 없음.** chipmunk/curl/freetype/glfw3/jpeg/luajit/openssl/png/tiff/webp/websockets/zlib 전부.
  → **최종 목표는 arm64 네이티브** (Rosetta 의존 금지 — §1 정책 참조). 프리빌트를 arm64로
  재빌드/교체하는 구체적 방법은 **§4.7 참조.** `ARCHS=x86_64` + Rosetta 빌드는 "코드 수정이
  맞는지"를 빠르게 확인하는 중간 검증 단계로만 써도 되고, 곧장 arm64로 가도 된다.
  특히 **LuaJIT**(x86_64-thin, 2.0계열은 arm64-macOS 미지원)가 최난관 — LuaJIT 2.1 재빌드
  또는 일반 Lua 5.1 전환 필요 (§4.7-3). mac용 일반 lua 프리빌트도 없음(`lua/lua/prebuilt`는 ios만).
- **iOS: 실기기 arm64 슬라이스 전부 존재** (armv7 i386 x86_64 arm64 fat). **arm64 시뮬레이터
  슬라이스는 없음** → Apple Silicon에서 시뮬레이터 빌드 불가, 실기기 빌드만 가능.
- external 버전: v3-deps-130 (openssl 1.1.0c, curl 7.52.1, freetype 2.5.5 등 — 2016년산).
- sqlite3는 Apple용 바이너리 없음(win32/win10만). glfw3·zlib은 iOS 프리빌트 없음(iOS는 SDK libz.tbd).

### 4.3 mac 타겟의 치명적 문제 (링크 전에 반드시 수정)
1. **mac 타겟이 게임 C++을 컴파일하지 않음.** Sources가 `mac/SimulatorApp.mm`, `mac/main.m`,
   `mac/ConsoleWindowController.m`, `Classes/AppDelegate.cpp` 4개뿐. 그런데 AppDelegate.cpp가
   `ATL::getInstance()`, `luaopen_VideoPlayer_core()`, `luaopen_TextInput_core()` 등을 호출
   → **ATL.cpp, VideoPlayer_iOS.cpp(스텁), TextInput.cpp, AsyncLoaderManager.cpp, SpriteAsync.cpp,
   utils.cpp, lua_utils.cpp, md5/* 를 mac Sources에 추가해야 링크됨** (iOS 타겟 소스 목록 참고).
2. `AppDelegate.h:11`이 비-iOS에서 `AL/al.h` include하는데 mac 타겟 헤더 경로에
   `Classes/openal/include`가 없음 → 추가 필요 (macOS OpenAL.framework는 `OpenAL/al.h` 경로임).
3. `HEADER_SEARCH_PATHS`의 `../Classes/protobuf-lite`는 디스크에 없음(무해하나 정리 대상).
4. `$(_COCOS_HEADER_MAC_BEGIN)` 류 변수는 cocos-console 주입 마커로 어디에도 정의 안 됨(빈 값 전개, 무해).
5. mac `OTHER_LDFLAGS`의 `-image_base 100000000 -pagezero_size 10000`은 LuaJIT 요구사항 — x86_64 유지 시 보존할 것.
6. 링크가 `libcurl.dylib`/`libz.dylib`/`libiconv.dylib`를 SDK 상대 경로로 참조 — 현 SDK에는
   `.tbd`만 있음 → `.tbd` 재참조 또는 `-lz -lcurl -liconv`로 교체.
7. 서명 설정 전무 — 로컬 실행은 ad-hoc 서명으로 충분.

### 4.4 iOS 타겟의 문제
1. deployment target 6.0(서브프로젝트는 5.0~8.1도 있음) → **15.0 이상으로 통일 상향.**
2. `VALID_ARCHS`/armv7 제거, `ARCHS=arm64`만.
3. 서브프로젝트들에 `SDKROOT=iphoneos11.0` 하드코딩 → `iphoneos`로.
4. 프레임워크 참조가 iPhoneOS7.0~9.3.sdk 절대경로로 하드코딩 → 재연결 필요.
5. **UIWebView가 cocos에 44곳 존재** (`cocos/ui/UIWebView*`, lua 바인딩 포함). SDK에서 제거된 API라
   컴파일 실패 + 앱스토어 거부 사유. **게임 코드는 UIWebView 미사용** → cocos 빌드에서 해당 소스
   제외(+ lua_module_register에서 webview 등록 제거)가 최선.
6. `cocos/ui/UIVideoPlayer-ios.mm`의 **MPMoviePlayerController도 SDK에서 제거됨** → 동일하게 제외 또는 AVPlayer 포팅.
7. `Info.plist`의 `UIRequiredDeviceCapabilities: opengles-1` 제거, PNG 런치이미지 →
   LaunchScreen.storyboard 신설 필요 (없으면 레터박스 + 제출 거부).
8. C++ 표준: `c++0x` 설정 → `gnu++14` 권장 + `-Wno-*` 다수 필요 예상.

### 4.5 비디오/오디오 서브시스템 현황
- ffmpeg 바이너리는 **android(armeabi 32bit)와 windows(x86 32bit)만 존재. mac/iOS용 없음.**
- iOS는 `VideoPlayer_iOS.cpp`(전 메서드 0/false 반환하는 스텁)를 컴파일 — mac도 이 스텁을
  쓰면 ffmpeg 없이 빌드 가능 (비디오 재생 기능은 비활성이 됨. 1차 목표에선 이걸로 타협 권장).
- OpenAL: mac은 헤더만 include되고 실제 호출(alcOpenDevice 등)은 Android 분기에만 있음.

### 4.6 기타
- 게임은 순수 Lua 구동: `VisNovel/src/`에 72개 .lua (LXVM.lua, PiniLib.lua, main.lua 등),
  `config.json`이 시뮬레이터 설정(960x640, landscape, consolePort 6050, uploadPort 6060).
- `VisNovel/simulator/`엔 win32 프리빌트만 있음. mac 시뮬레이터 산출물은 빌드로 새로 만들어야 함.
- `.cocos-project.json`의 engine_version 표기는 3.7rc0이지만 실제 코드는 3.15.1.

### 4.7 arm64 네이티브 전환 가이드 (Rosetta 탈출 — mac의 본선 작업)

원칙: **Xcode 프로젝트 구조는 유지하고, `external/*/prebuilt/mac/*.a`를 arm64(가능하면
arm64+x86_64 universal)로 교체**한다. universal로 만들면 기존 링크 설정을 안 건드려도 되고
인텔 맥 지원도 유지된다.

**1) 재빌드 없이 시스템 라이브러리로 대체 (가장 먼저 할 것)**
- `zlib` → SDK `libz.tbd`, `iconv` → `libiconv.tbd` (이미 그렇게 링크 중 — §4.3-6의 .tbd 교체만)
- `curl` → SDK `libcurl.tbd` (macOS 내장 curl, arm64 포함). 프리빌트 libcurl.a 링크 제거.
- `openssl` + `websockets` → **게임 Lua 코드가 websocket을 쓰는지 먼저 확인**
  (`VisNovel/src`와 샘플 프로젝트에서 `WebSocket` grep). 안 쓰면 cocos의
  `network/WebSocket*` 소스와 lua 바인딩을 빌드에서 제외해 **openssl 의존 자체를 제거**(권장).
  쓰면 openssl 3.x arm64 재빌드 필요.

**2) 소스에서 arm64/universal 재빌드가 필요한 것**
png, jpeg(libjpeg-turbo 권장), tiff, webp, freetype, chipmunk, glfw.
- 로컬에 brew/cmake가 없으므로 **`pip3 install cmake ninja`로 조달** (pip 네트워크 가능 확인됨).
- 공통 패턴: `cmake -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
  -DBUILD_SHARED_LIBS=OFF` → 산출 .a로 `external/<lib>/prebuilt/mac/`의 파일을 교체.
- 버전 선택: 헤더(`external/<lib>/include/`)까지 같이 갱신할 것. API 호환성은
  freetype 2.13/libpng 1.6.x/tiff 4.x/webp 1.x 모두 cocos 3.15 사용 범위에서 문제없는 수준.
  glfw는 3.4 사용 — `CCGLViewImpl-desktop.cpp`가 쓰는 API 위주로 컴파일 에러만 정리하면 됨.
  chipmunk은 cocos가 요구하는 6.2.x 소스가 `external/chipmunk`에 없으므로 업스트림
  Chipmunk2D 6.2.2 소스로 빌드.
- **재현 가능하게 `scripts/build-deps-apple.sh` 하나로 스크립트화**(다운로드 URL·버전 핀 명시)
  해서 커밋할 것. 다음 사람이 같은 문제를 다시 풀지 않도록.

**3) Lua VM (최난관)**
- 권장: **LuaJIT 2.1** (openresty/luajit2 브랜치가 관리 잘 됨). arm64 macOS 지원.
  `MACOSX_DEPLOYMENT_TARGET=11.0 make` + `lipo`로 universal 합성 → `external/lua/luajit/prebuilt/mac/libluajit.a` 교체.
- arm64에서는 mac 타겟 `OTHER_LDFLAGS`의 `-image_base 100000000 -pagezero_size 10000`
  **제거** (x86_64 LuaJIT 전용 핵. arm64 LuaJIT는 불필요하며 넣으면 오히려 문제).
  x86_64 슬라이스를 병행 유지하는 동안에는 arch별 xcconfig 분기(`OTHER_LDFLAGS[arch=x86_64]`)로.
- 대안: 일반 **Lua 5.1.5** (가장 단순·확실, JIT 없어 성능 하락). cocos lua-bindings는
  Lua 5.1 API 기준이라 어느 쪽이든 호환. LuaJIT 빌드가 계속 말썽이면 미련 없이 이쪽으로.

**4) 검증 절차**
- 교체 후 `lipo -info external/*/prebuilt/mac/*.a`로 arm64 포함 전수 확인
- `xcodebuild ... ARCHS=arm64 ONLY_ACTIVE_ARCH=NO` 빌드 → 네이티브 실행 확인
  (`file pini_remote-desktop.app/Contents/MacOS/*`가 arm64인지, Activity Monitor에서
  "Apple" 아키텍처로 뜨는지)

**5) iOS에도 같은 원칙 적용 (후속)**
- 현 iOS 프리빌트는 실기기 arm64가 있어 당장은 빌드되지만 2016년산이고 arm64 시뮬레이터
  슬라이스가 없다. 2)의 빌드 스크립트를 iOS/iOS-simulator까지 확장해 **xcframework**로
  묶는 것을 Phase 3 후속 과제로 잡을 것 (시뮬레이터 개발 경험 + 의존성 보안 업데이트 동시 해결).

### 4.8 vendored cocos2d-x 커스텀 패치 식별 (엔진 교체·업그레이드 전 필수)
저장소의 cocos2d-x는 vendored라 **업스트림 3.15.1 대비 커스텀 수정이 섞여 있을 수 있다.**
장기 로드맵(§6 말미)의 어떤 경로를 택하든, 먼저 업스트림 cocos2d-x 3.15.1 릴리즈 tarball과
`frameworks/cocos2d-x`를 diff 떠서 커스텀 패치 목록을 문서화할 것. 이 목록이 없으면
엔진 업그레이드 시 기능이 조용히 사라진다.

## 5. 조사 결과 C — Android [조사 완료]

### 5.1 두 개의 안드로이드 프로젝트, 진짜는 ant 쪽
- **`proj.android` (ant/Eclipse ADT) = 실제 출시 프로젝트.** 게임 코드 전부 여기 있음:
  `AppActivity.java`(850줄, Cocos2dxActivity 상속 + IDownloaderClient), 로컬 알림
  `AlarmReceive.java`, OBB 확장파일 다운로더, **AIDL v3 인앱결제**(IabHelper 일가 +
  `IInAppBillingService.aidl`; Lua에서 `_IAB_Buy` 등으로 호출), 광고 SDK jar들(Cauly,
  Adop, UplusAD, Vungle 3.3), Fabric/Crashlytics 2.5.2, Play Services 6.5(2014년),
  play_licensing, play_apk_expansion (`frameworks/android-extension/`의 ant 라이브러리 3개 참조).
- **`proj.android-studio` (gradle) = 게임 코드가 없는 cocos 3.15 순정 템플릿.** AGP 1.3.0 +
  Gradle 2.4 + jcenter(사망) + compileSdk 22. 미정의 프로퍼티(`PROP_TARGET_SDK_VERSION`)로
  현 상태로는 configure조차 안 됨. **부활시키지 말고, proj.android의 소스를 새 Gradle
  프로젝트로 포팅하는 것이 정석.**
- `Engine/android_compile.py`: python2 스크립트. 매니페스트 package를
  `com.nooslab.pini_remote(_landscape)`로 바꾸고 `cocos compile -p android --ap android-21`
  호출 후 APK를 `Engine/android/`로 복사하는 래퍼. adb 경로가 Windows 하드코딩.

### 5.2 매니페스트/버전 현황
- package `com.nooslab.pini_remote_landscape`, versionCode 56 / 1.937,
  **minSdk 9, targetSdk 없음**(=9로 간주됨). 런처는 `org.cocos2dx.lua.AppActivity` (landscape).
- `AlarmReceive.java`가 API 11 이전에 제거된 `new Notification(icon,ticker,when)` +
  `setLatestEventInfo()` 사용 → 최신 SDK에서 컴파일 불가. NotificationCompat + 채널로 재작성 필요.

### 5.3 네이티브 빌드 현황
- `Application.mk`: **`APP_STL := gnustl_static`** (NDK r18+에서 제거됨 → `c++_static` 전환 필수),
  `-std=c++11 -frtti -fsigned-char`, APP_ABI 미지정 → cocos 콘솔 기본값 **armeabi**로 빌드돼 왔음
  (`proj.android/libs/`에 armeabi만 존재).
- cocos external 안드로이드 프리빌트(chipmunk/curl/freetype2/jpeg/openssl/png/tiff/webp/websockets/zlib):
  **armeabi, armeabi-v7a, arm64-v8a, x86 제공** (x86_64 없음) → arm64-v8a는 커버됨.
- **진짜 ABI 병목은 게임 전용 프리빌트:**
  - `Classes/ffmpeg/lib/android/`: armeabi(32bit) .so만 존재 (libavcodec-55 등 8개)
  - `Classes/openal/libs/`: armeabi, armeabi-v7a만. `openal/Android.mk`가
    `libs/armeabi/libopenal.so` 경로를 **하드코딩**
  → **arm64-v8a 빌드가 현재 불가능** (플레이스토어는 2019년부터 64bit 필수).
  ffmpeg/openal을 arm64로 재빌드하고 Android.mk를 `$(TARGET_ARCH_ABI)` 기반으로 고치거나,
  1차 릴리즈에선 mac과 동일하게 **비디오 기능을 스텁으로 떼는 것**이 현실적.
- `build-cfg.json`이 빌드 시 `src/`, `res/`, `config.json`을 assets로 복사.

### 5.4 EOL 의존성 (전부 교체/제거 대상)
AIDL v3 결제(→ Play Billing 7+ 재작성), Play Services 6.5, Fabric/Crashlytics(서비스 종료),
Apache HttpClient jar(`android-async-http`, `httpclient-4.4.1.1` — API 23+에서 클래스패스 제거),
광고 SDK 4종(전부 폐물), OBB expansion(→ Play Asset Delivery 또는 그냥 APK/AAB 내장), LVL licensing.

### 5.5 ⚠️ 저장소에 커밋된 시크릿
- `proj.android/piniremote.keystore` + `ant.properties`에 **평문 비밀번호**(02881212, alias
  `com.nooslab.pini_dev`), `fabric.properties`의 apiSecret, 매니페스트의 Fabric API key.
- 공개 저장소라면 이미 유출 상태. 새 keystore 발급 + 시크릿 파일 git 제거(.gitignore) 권장.
  기존 앱 업데이트 배포가 목표라면 이 keystore가 필요하므로 삭제 전 사용자 확인 필수.

## 6. 전체 실행 계획 (우선순위 순)

### Phase 1 — macOS 엔진 빌드 — ✅ **완료 (2026-07-25). 결과는 §9 참조**

아래는 착수 당시의 계획이며, 실제 수행 결과와 계획에서 어긋난 부분은 §9에 정리했다.

1. mac 타겟 Sources에 누락된 게임 C++ 추가 (§4.3-1 목록 — iOS 타겟 소스 목록을 기준으로,
   단 `VideoPlayer.cpp`가 아니라 스텁인 `VideoPlayer_iOS.cpp`를 사용)
2. mac 타겟 헤더 경로에 `$(SRCROOT)/../Classes/openal/include` 추가 (§4.3-2)
3. `.dylib` 링크 참조를 `.tbd`/`-l` 플래그로 교체하고, 시스템 라이브러리로 대체 가능한
   프리빌트(curl/zlib/iconv, 가능하면 openssl+websockets 제거)를 먼저 털어냄 (§4.7-1)
4. (선택) `ARCHS=x86_64` + Rosetta로 중간 스모크 테스트 — **코드 수정의 정합성만 빨리
   확인하는 용도.** 이 상태를 완성으로 취급하지 말 것 (Rosetta는 macOS 27 이후 소멸 — §1).
5. §4.7-2·3에 따라 남은 프리빌트를 arm64(universal) 재빌드: 이미지/폰트/물리 계열 +
   LuaJIT 2.1 (또는 Lua 5.1 전환). `scripts/build-deps-apple.sh`로 스크립트화해 커밋.
6. `xcodebuild -target pini_remote-desktop ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build`
   → 컴파일 에러 반복 수정. C++ 표준은 `gnu++14` 강제 + `-Wno-*` 완화.
   cocos2d-x 쪽 수정은 최소한으로. 서브프로젝트 3개(cocos2d_libs, lua_bindings, libsimulator)도
   `xcodebuild` 커맨드라인 오버라이드로 같이 처리 (프로젝트 파일 수정 최소화).
   arm64에서는 `-image_base/-pagezero_size` 링커 플래그 제거 (§4.7-3).
7. 산출물 .app을 `Engine/OSX.app`로 교체 배치(기존 것은 백업) 후 실행 확인
8. 성공 기준: **arm64 네이티브로** 창이 뜨고 45674 포트 리슨, 에디터에서 씬 전송 시 렌더링.
   (`file`로 바이너리가 arm64인지 확인)

### Phase 2 — 에디터 py3/PySide6 포팅 — ✅ **완료 (2026-07-25). 결과는 §10 참조**

### Phase 3 — iOS — ✅ **완료 (2026-07-26). 결과는 §11 참조**

아래는 착수 당시의 계획이며, 실제 결과와 어긋난 부분은 §11에 정리했다.

1. deployment target 15.0으로 통일 상향(메인+서브프로젝트 3개), `VALID_ARCHS` 제거,
   `ARCHS=arm64`, `SDKROOT=iphoneos11.0` 하드코딩 제거
2. **UIWebView 소스를 cocos 빌드에서 제외** (`cocos/ui/UIWebView*`, `UIWebViewImpl-ios.*`,
   lua 바인딩의 webview auto/manual 파일 + `lua_module_register.h`에서 등록 해제) —
   게임 코드는 미사용이므로 안전. `UIVideoPlayer-ios.mm`(MPMoviePlayer)도 동일 처리.
3. 하드코딩된 옛 SDK 절대경로 프레임워크 참조 재연결, `.dylib`→`.tbd`
4. `Info.plist` `opengles-1` capability 제거, LaunchScreen.storyboard 신설
5. `xcodebuild -sdk iphoneos -target pini_remote-mobile build CODE_SIGNING_ALLOWED=NO`로
   서명 없이 빌드 검증 (프리빌트 .a에 arm64 실기기 슬라이스 있음 — §4.2)
- 성공 기준: 서명 없는 arm64 실기기 빌드 성공. 실제 .ipa 서명/제출은 사용자 Apple 계정 필요
  (→ 사용자 확인 지점). 시뮬레이터는 arm64 슬라이스 부재로 불가(§4.2) — 실기기로 테스트.

### Phase 4 — Android
1. Android cmdline-tools + SDK 35 + NDK r26~27 설치 (로컬에 아무것도 없음)
2. **새 Gradle 프로젝트 작성** (AGP 8.x + gradle wrapper): `proj.android`의 java 소스/AIDL/
   assets 로직을 포팅. `proj.android-studio`는 참고용으로만 (부활 금지, §5.1).
   네이티브는 ndk-build(`Android.mk`) 유지가 최단 경로 — AGP 8은 `externalNativeBuild.ndkBuild` 지원.
3. `APP_STL := c++_static` 전환, `APP_ABI := arm64-v8a armeabi-v7a`
4. ffmpeg(armeabi만 존재)/openal 문제: 1차는 **VideoPlayer를 iOS처럼 스텁으로 대체**하고
   ffmpeg 링크 제거 + openal은 arm64 재빌드(오디오 필수 여부 확인 후). `openal/Android.mk`의
   armeabi 하드코딩 수정 (§5.3)
5. `AlarmReceive.java`를 NotificationCompat + NotificationChannel로 재작성 (§5.2)
6. 1차 릴리즈 범위 축소: 광고 SDK 4종/Fabric/expansion/licensing **제거**, AIDL 결제는
   기능 플래그로 비활성 (Play Billing 7+ 재작성은 별도 후속 작업 — Lua 인터페이스
   `_IAB_Buy/_IAB_Check/_IAB_Consume`는 시그니처 유지한 채 스텁화)
7. targetSdk 35 / minSdk 24, 매니페스트 현대화 (receiver `exported` 명시, 저장소 권한 정리)
- 성공 기준: `./gradlew assembleDebug`로 arm64-v8a 포함 APK 생성

### Phase 5 — 에디터의 Export 파이프라인 (후순위)
- Export_Windows/Export_Android는 Windows 도구체인 래퍼라 mac에서는 재작성 필요.
  1차 릴리즈에서는 "에디터에서 개발+미리보기, 배포 빌드는 Xcode/gradle 직접 실행" 워크플로로 타협 가능.

### 장기 로드맵 — "최신 환경 기준" 코드로 (Phase 1~4 완료 후)
Phase 1~4는 2015년산 코드를 현행 도구에서 **빌드되게** 만드는 작업이고, 아래는 앞으로도
**계속 살아있게** 만드는 작업이다. 우선순위 순:

1. **렌더러 수명 문제**: cocos 3.15는 OpenGL 전용. OpenGL은 macOS/iOS에서 deprecated이며
   Rosetta처럼 언젠가 제거된다. 선택지는 둘:
   - **axmol 엔진으로 이관 (권장)** — cocos2d-x의 커뮤니티 후계 프로젝트. Metal 렌더러,
     최신 Xcode/AGP/NDK, arm64 전 플랫폼, Lua 바인딩 유지. cocos 3.x API와 가까워
     이관 비용이 cocos 4.0 대비 크게 나쁘지 않고, 이후 유지보수를 업스트림에 맡길 수 있음.
   - cocos2d-x 4.0 이관 — Metal은 얻지만 2019년 이후 사실상 개발 중단이라 같은 문제가 재발함.
   - 어느 쪽이든 **§4.8의 커스텀 패치 diff가 선행 조건.** 게임 쪽 커스텀 C++
     (ATL, VideoPlayer, TextInput, lua_utils)은 엔진 API 접점이 좁아 이식 가능성 높음.
2. **의존성 현행화**: §4.7의 빌드 스크립트를 CI(GitHub Actions)로 옮겨 openssl/curl/freetype
   등을 주기적으로 최신 버전으로 재빌드. 2016년산 프리빌트를 다시는 저장소에 박제하지 말 것.
3. **에디터 배포 현대화**: py2exe/NSIS/자체 updator 대신 macOS는 py2app 또는 PyInstaller +
   서명/공증(notarization), Windows는 PyInstaller. `Editor/updator`는 폐기 확정.
4. **Python/Qt 추적**: PySide6는 Qt 온라인 릴리즈 주기가 빠름 — requirements.txt에 버전 핀 +
   연 1회 업그레이드 관례를 문서화.
5. **비디오 재생 복원**(선택): 전 플랫폼에서 스텁화한 VideoPlayer를 ffmpeg 재도입 대신
   플랫폼 네이티브(AVPlayer / ExoPlayer/Media3)로 재구현하는 편이 유지보수가 싸다.

## 7. 주의사항 / 함정 목록

- **시크릿 유출 (§5.5)**: 서명 keystore와 평문 비밀번호가 저장소에 커밋되어 있음.
  기존 앱의 업데이트 배포에 필요한 keystore이므로 **삭제/교체 전 반드시 사용자에게 확인.**
- **Editor/pini에 win32 DLL 35MB가 커밋되어 있음** — 지우면 diff는 깔끔하지만 Windows 지원을
  유지하려면 남겨둘 것. (이번 작업 범위는 mac 추가이지 Windows 제거가 아님)
- `Editor/pini/main.py`의 `ERROR_LOG.txt` 열기가 cwd 의존 — 실행 cwd는 `Editor/pini`여야 함.
- 에디터 dev/release 분기: `pini/conf/config_dev.py` vs `config_live.py`의 `__RELEASE__` 플래그.
- 엔진 TCP 프로토콜(45674)은 md5 체크섬 기반 파일 동기화 — 프로토콜 자체는 플랫폼 중립.
- 샘플 프로젝트 9개가 `Editor/sample_proj/`에 있음 (한국어 파일명) — 테스트에 활용.
- 커밋 메시지에 한국어 사용 (기존 히스토리 관례).

## 8. 이어받는 세션에 대한 지시

1. 이 문서의 §4, §5가 "조사 진행 중"이면, 백그라운드 조사가 유실된 것이므로
   해당 섹션의 조사 항목을 직접 다시 조사할 것 (Explore 에이전트 권장).
2. Phase 1부터 순서대로. 각 Phase 완료 시 이 문서의 해당 섹션에 결과를 갱신하고 커밋할 것.
3. 빌드 로그를 통째로 붙이지 말고, 에러 유형별로 요약해 문서화할 것.
4. 파괴적 작업(대량 삭제, force push) 전에는 사용자 확인.

## 9. Phase 1 수행 결과 — macOS arm64 네이티브 (2026-07-25)

### 9.1 결과
`pini_remote-desktop.app` 이 **arm64 네이티브**로 빌드/실행되고 45674 포트를 리슨한다.
비-시스템 동적 의존성은 없다 (`otool -L` 결과가 전부 `/usr/lib`, `/System`).
Rosetta 중간 검증 단계(계획 4번)는 **건너뛰고 곧바로 arm64 로 갔고, 그래도 문제가 없었다.**

빌드 방법:
```
scripts/build-deps-apple.sh     # 1회. external 의존성을 arm64 로 빌드 + 헤더 갱신
scripts/build-mac.sh            # 앱 빌드 (Release)
```
산출물: `Engine/VisNovel/frameworks/runtime-src/proj.ios_mac/build/Release/pini_remote-desktop.app`

> `Engine/OSX.app` 교체는 **아직 하지 않았다.** 기존 것은 x86_64 이고 실행 파일 이름도
> `novel Mac`(번들 ID `org.cocos2dx.hellolua`)이라 지금 산출물과 구조가 다르다.
> 에디터(`Menu.py`)가 이 경로를 `open` 으로 실행하므로, Phase 2 에서 에디터의 darwin 분기를
> 손볼 때 (리소스 동기화 + `open --args`, §3.1) 함께 정리하는 편이 안전하다.

### 9.2 사전조사(§4) 대비 정정 사항 — **다음 사람이 꼭 볼 것**

1. **앱 타겟은 프리빌트를 하나도 링크하지 않고 있었다.** mac 타겟 `OTHER_LDFLAGS` 가
   `$(_COCOS_LIB_MAC_BEGIN)/_END` 마커에만 의존하는데 이 변수는 저장소 어디에도 정의가 없다
   (cocos-console 이 주입하던 것). 그래서 png/jpeg/freetype/chipmunk/glfw/luajit 링크 플래그를
   프로젝트에 **명시적으로** 넣었다. §4.3-5 가 말한 `-image_base/-pagezero_size` 보존 문제는
   arm64 로 가면서 자연히 제거.
2. **`SDKROOT = iphoneos11.0` 하드코딩은 iOS 만의 문제가 아니다** (§4.4-3). `cocos2d_libs.xcodeproj`
   의 **`libcocos2d Mac` 타겟에도** 걸려 있어 mac 빌드가 `unable to find sdk` 로 즉시 죽는다.
   서브프로젝트 파일을 고치는 대신 `scripts/build-mac.sh` 의 커맨드라인 오버라이드로 처리했다.
3. **vendored chipmunk 헤더는 6.2.x 가 아니라 7.0.1** 이다 (§4.7-2 정정). 업스트림 7.0.3 으로 빌드.
4. **cocos2d-x 3.15.1 본체는 Xcode 26 / arm64 에서 거의 그대로 컴파일된다.** 1000개 넘는 소스 중
   손댄 것은 아래 목록이 전부다. 이 항목이 Phase 1 의 가장 큰 리스크였는데 실제로는 작았다.

### 9.3 의존성 (`scripts/build-deps-apple.sh`, 버전 고정)

| 라이브러리 | 처리 | 버전 |
|---|---|---|
| zlib / curl / iconv / sqlite3 | **시스템 SDK `.tbd` 로 대체** (프리빌트 폐기) | macOS 26.2 SDK |
| openssl | **의존 자체를 제거** (websockets 를 SSL 없이 빌드) | — |
| libpng | 소스 빌드 + 헤더 갱신 | 1.6.44 (기존 1.6.16) |
| libjpeg | libjpeg-turbo 로 교체 + 헤더 갱신 | 3.0.4 (기존 IJG 9.0) |
| libtiff | 소스 빌드, 코덱 전부 off | 4.7.0 (기존 4.0.3) |
| libwebp | 소스 빌드, sharpyuv 를 libwebp.a 에 병합 | 1.4.0 (기존 0.2.1) |
| freetype | 소스 빌드 + 헤더 트리 교체 | 2.13.3 (기존 2.5.5) |
| chipmunk | 소스 빌드 + 헤더 교체 | 7.0.3 (기존 7.0.1) |
| glfw3 | 소스 빌드 + 헤더 교체 | 3.4 (기존 3.2.0) |
| libwebsockets | **SSL 없이** 빌드 (게임은 WebSocket 미사용) | 2.1.0 고정 — cocos 코드가 lws 2.1 API 기준이라 올리면 깨진다 |
| Lua VM | **LuaJIT 2.1** 브랜치. arm64 macOS 정상 동작 | v2.1 (기존 x86_64 2.0계열) |

- 전부 `arm64` 단독 빌드. universal 이 필요하면 `ARCHS="arm64;x86_64" scripts/build-deps-apple.sh`.
- 헤더와 라이브러리를 **항상 같이** 갱신한다. 특히 jpeg 9 헤더 + libjpeg-turbo 조합은 struct
  레이아웃이 어긋나 런타임에 깨지므로 절대 섞지 말 것.

### 9.4 수정한 코드 — 에러 유형별

**(A) 2016년 코드 ↔ macOS 26 SDK 심볼 충돌**
- `cocos/audio/mac/CDXMacOSXSupport.{h,mm}`, `CDAudioManager.{h,m}`
  - macOS 26 SDK 가 `AudioToolbox/AudioSession.h` 를 macOS 에도 노출하면서 CocosDenshion 의
    shim 과 충돌(열거자 중복 정의 + SDK 쪽 `AudioSessionGetProperty` 가 `API_UNAVAILABLE(macos)`).
    → shim 을 `CDX` 접두어로 분리(`CDXAudioSessionGetProperty`, `kCDXAudioSessionProperty_*`).
  - 같은 이유로 ObjC 클래스 `AVAudioSession` 이 시스템 private framework 와 이름 충돌
    (런타임이 "may cause mysterious crashes" 경고) → `CDXAVAudioSession` 으로 개명.
  - 덤으로 shim 이 `outData` 를 채우지 않아 호출부가 미초기화 `CFStringRef` 를 읽던 버그도 수정.
- `cocos/2d/CCFontAtlas.cpp` — 최신 SDK 의 `iconv_t` 는 `void*` 가 아니라 `__tag_iconv_t*` →
  `iconv()/iconv_close()` 호출에 명시 캐스팅.

**(B) 의존성 버전 상승에 따른 API 변화**
- `cocos/platform/CCGLView.h` — glfw 3.3+ 의 `glfw3native.h` 가 `<objc/objc.h>` 를 직접
  include 하므로 cocos 의 `typedef void* id;` 와 이중 정의. Apple 에선 objc 의 진짜 `id` 를 쓰도록.
- `cocos/platform/desktop/CCGLViewImpl-desktop.h` — **가장 파급이 컸던 건.**
  `glfw3native.h` 가 `<ApplicationServices/...>`(→ Carbon `MacTypes.h`)를 끌어오는데, 이 헤더는
  `cocos2d.h` 에 포함되므로 전역 `Rect`/`Size` 오염이 cocos + lua-bindings + libsimulator
  **전 번역단위**로 퍼져 `cocos2d::Rect/Size` 참조가 모호해진다. → include 를 없애고 실제로
  필요한 `glfwGetCocoaWindow` 선언만 직접 둠.
- `cocos/physics/CCPhysicsWorld.cpp` — chipmunk 7.0.3 부터 `chipmunk.h` 가 `cpHastySpace.h` 를
  자동 include 하지 않음 → 명시 include. 단 이 헤더엔 `extern "C"` 가 없어 그대로 넣으면
  C++ 맹글링으로 링크가 깨진다 → `extern "C" { }` 로 감쌀 것.
- `extensions/physics-nodes/CCPhysicsDebugNode.cpp` — chipmunk 7.0.3 이 내부 struct 정의를
  `chipmunk_private.h` → `chipmunk_structs.h` 로 분리하고 `CP_PRIVATE` 매크로를 없앰.
- `cocos/scripting/lua-bindings/manual/CCLuaStack.cpp`,
  `runtime-src/Classes/md5/compat-5.2.{c,h}` — LuaJIT 2.1 이 Lua 5.1 의 deprecated 별칭
  `luaL_reg` 를 제거하고, 반대로 Lua 5.2 의 `luaL_setfuncs` 를 제공한다
  (게임 쪽 compat 구현과 duplicate symbol).

**(C) 렌더링 버그 — 글자가 색 노이즈로 깨지던 문제 (mac 전용)**
- `cocos/platform/mac/CCDevice-mac.mm` — 시스템 폰트 라벨 텍스처를 만들 때
  `[NSImage lockFocus]` + `initWithFocusedViewRect:` 로 얻은 비트맵에서
  `width*height*4` 바이트를 그대로 memcpy 했다. 즉 "32bpp RGBA8888, `bytesPerRow == width*4`"
  라고 가정한 것인데, **최신 macOS 에서 이 비트맵은 채널당 16비트 딥컬러로 돌아온다.**
  실측(162x28 라벨): `bitsPerPixel=64`, `bytesPerRow=1296` (가정값 32 / 648의 정확히 2배).
  샘플 크기와 stride 가 동시에 어긋나 글자가 자홍/녹색 노이즈로 깨졌다.
  → 픽셀 크기·행 간격·샘플 크기·채널 순서를 직접 지정한 `NSBitmapImageRep` 에 그리도록 변경.
  검증: 같은 조건으로 두 경로를 재현해 비교한 결과 불투명 픽셀 중 R/G/B 가 어긋난 비율이
  옛 경로 89.2% → 새 경로 0.0%.
  (iOS 쪽 `CCDevice-ios.mm` 에 같은 문제가 있는지는 Phase 3 에서 확인할 것.)

**(D) 게임 코드 (runtime-src/Classes)**
- `AppDelegate.h` — mac 에서는 안드로이드용 `Classes/openal` 헤더 대신 시스템
  `<OpenAL/al.h>` 를 쓰도록(실제 `alc*` 호출은 안드로이드 분기에만 있음).
- `AppDelegate.cpp` — mac 도 iOS 처럼 **스텁** `VideoPlayer_iOS.h` 를 쓰도록.
  (ffmpeg 프리빌트가 android/windows 32bit 만 있어 mac 은 애초에 불가 — §4.5)

**(E) `pini_remote.xcodeproj` (mac 타겟만)**
- 누락돼 있던 게임 C++ 13개를 Sources 에 추가 (§4.3-1 지적대로 mac 타겟은 게임 코드를
  전혀 컴파일하지 않고 있었다): `ATL/TextInput/AsyncLoaderManager/SpriteAsync/utils/
  lua_utils/AppDelegateEvent/VideoPlayer_iOS` + `md5/*`.
- Resources 에 `src`, `res` 폴더 레퍼런스 추가 (iOS 타겟에는 있었으나 mac 에는 없었음).
- 존재하지 않는 `HEADER_SEARCH_PATHS` 항목 `../Classes/protobuf-lite` 제거.
- 현행 SDK 에 없는 `usr/lib/*.dylib` 참조 3개(libz/libcurl/libiconv) 제거 → `-l` 플래그로.
- `ARCHS = arm64`, `MACOSX_DEPLOYMENT_TARGET = 11.0`, `CLANG_CXX_LANGUAGE_STANDARD = gnu++14`,
  프리빌트 `LIBRARY_SEARCH_PATHS` + 링크 플래그 추가, `-image_base/-pagezero_size` 제거.

### 9.5 알려진 제약 (의도된 것)
- **비디오 재생 비활성.** 전 플랫폼 스텁 방침(§4.5). 복원은 장기 로드맵 5번.
- **WebSocket 은 `ws://` 만.** openssl 을 되살리지 않으려고 SSL 없이 빌드. 게임 Lua 는 미사용.
- **arm64 전용.** 인텔 맥 지원이 필요하면 §9.3 의 universal 옵션으로 의존성을 다시 만들고
  `pini_remote.xcodeproj` 의 `ARCHS` 를 되돌린 뒤, LuaJIT x86_64 슬라이스에 대해서만
  `OTHER_LDFLAGS[arch=x86_64]` 로 `-image_base/-pagezero_size` 를 되살려야 한다 (§4.7-3).
- `external/*/prebuilt/mac/*.a` 는 이번에 arm64 산출물로 **교체**되어 커밋되었다.
  장기적으로는 CI 로 옮기고 저장소에서 빼는 것이 맞다 (장기 로드맵 2번).
- cocos 쪽 수정은 §4.8 의 "업스트림 대비 커스텀 패치" 목록에 이번 것도 포함시켜야 한다.
  구분을 위해 이번 수정은 전부 주석에 이유를 적어 두었다.

## 10. Phase 2 수행 결과 — 에디터 py3 / PySide6 포팅 (2026-07-25)

### 10.1 결과
- `Editor/pini` + `Editor/Noriter` 의 **모듈 47개가 전부 import 되고**, 에디터가 끝까지 부팅해
  런처까지 뜬다.
- 검증한 전체 시나리오: **에디터 구동 → 프로젝트 열기 → lupa 프리뷰 초기화 → LNX 컴파일 →
  엔진(arm64) 기동 → TCP 파일 동기화 67개 → 씬 실행 → 종료** 까지
  **예외 0건 / 종료코드 0** 으로 통과 (자동 구동 테스트).
- 실행이 실제로 되기까지 잡아야 했던 것들은 §10.9(프로토콜) 과 §10.10(프로세스 급사) 참조.

실행 방법:
```
scripts/build-editor-natives.sh          # 1회. atl.so (arm64) 생성
cd Editor/pini && python3 main.py
```

### 10.2 변환 도구
Python 3.13 은 `2to3`/`lib2to3` 가 제거되었다. 유지보수 포크인 **`fissix`** (`pip install fissix`)
로 fixer 를 골라 돌렸다. 제외한 fixer 와 그 이유:
- `fix_idioms` / `fix_ws_comma` / `fix_set_literal` — 순수 미관 변경이라 diff 만 커진다.
- `fix_reload` — `imp.reload`(deprecated) 로 바꾼다. `importlib.reload` 로 직접 처리했다.
- `fix_import` — 이 코드베이스는 `pini/` 루트 기준 **절대 import** 라 py3 에서도 그대로 동작한다.
  (암시적 상대 import 는 Windows 전용 `pepy/` 에만 있다.)

### 10.3 자동 변환이 **틀리게** 고친 것 — 반드시 알고 있어야 할 함정
1. **`compiler.py` 의 LNX 렉서가 통째로 죽었다.** 이 모듈은 `def filter(lexer, add_endmarker)`
   라는 **자체 제너레이터**를 정의해 두는데, 2to3 의 `fix_filter` 가 내장 filter 로 착각해
   `list(filter(...))` 로 감쌌다. 그러면 `token()` 의 `next()` 가 리스트에서 터진다.
   → 같은 사고를 찾으려면 "모듈이 내장 이름(filter/map/zip/range)을 재정의했는지" 를 먼저 볼 것.
   이 저장소에서는 `compiler.py` 한 곳뿐이었다.
2. **`fix_unicode` 가 `unicode("가","utf-8")` 을 `str("가","utf-8")` 로 바꿔 놨다.** py3 에서
   `str(str, enc)` 은 TypeError 다. 소스가 이미 utf-8 이므로 리터럴만 남기면 된다 (17곳).

### 10.4 py2 → py3 (문법 외)
- `os_encoding.py` **삭제.** cp949/utf-8 을 오가던 인코딩 모델을 없애고 str 로 통일 (§3.5-1).
  `updator/` 는 자체 사본을 갖고 있어 영향이 없다.
- `reload(sys)` + `sys.setdefaultencoding("utf-8")` 34개 파일에서 제거.
- `mbcs`(윈도우 전용 코덱)로 디코드하던 곳 → utf-8 / 디코드 불필요 (`ATL.py`, `LoaderView`,
  `Export_Android`, `FontManager`).
- `PJOIN()` 3곳: 경로 조각을 로케일 bytes 로 encode 하고 구분자를 `\` 로 강제하던 것을
  str + `os.sep` 으로. 이게 없으면 mac 에서 `tempSave\PROJ` 같은 경로가 만들어진다.
- `ProjectController.compileProjWork` 의 `+ "\\"` → `os.sep`.
  **이 버그 때문에 컴파일이 `module\libdef.lnx` 를 찾다 죽었고, 파일명에 백슬래시가 들어간
  파일이 실제로 만들어졌다.** (저장소 전체에서 mac 을 깨뜨리는 백슬래시 조립은 이 한 곳뿐이었다.
  나머지 60여 곳은 `"\\"→"/"` 정규화라 mac 에서 무해하고, 역변환은 전부 Windows 익스포트 전용이다.)
- `base64.encodestring`(py3.9 제거) → `encodebytes` + `.decode("ascii")`.
- `os.system('start "" ...')`(윈도우 cmd 내장) → `QDesktopServices.openUrl` (Menu, AssetLibrary).
- `Exception.message` → `str(e)`.

### 10.5 Qt4(PySide) → Qt6(PySide6)
- 임포트 47개 파일 전환. `from PySide.QtGui import *` 는 **QtGui + QtWidgets 두 줄**로 풀고,
  `QtGui.<위젯>` 참조는 `QtWidgets.<위젯>` 으로 (Qt5 에서 위젯이 분리됐고, Qt6 에서 QAction 은
  다시 QtGui 로 돌아왔다).
- 제거된 API 대응:
  `QApplication.desktop()`→`primaryScreen().geometry()`, `QRegExp`→`QRegularExpression`,
  `QDesktopServices.storageLocation`→`QStandardPaths.writableLocation`,
  `QFontMetrics.width`→`horizontalAdvance`, `setTabStopWidth`→`setTabStopDistance`,
  `trUtf8`→`tr` (22곳), `QPalette.Background`→`QPalette.Window`,
  `QGraphicsView.matrix()`→`transform()`, `QGraphicsItem.scale(sx,sy)`→
  `setTransform(QTransform.fromScale(...), True)`, `QTextStream.setCodec`→`setEncoding` (25곳),
  `Qt.CTRL+Qt.Key_X`→`|`.
- **QtWebKit → QTextBrowser.** 도움말 툴팁 2개(`ExplainWebView`/`ExplainHoverWebView`)는
  "HTML 조각 표시 + 링크는 외부 브라우저" 가 전부라 무거운 QtWebEngine 대신 QTextBrowser 로
  충분하다. 공통 베이스 `ExplainBrowserBase` 를 두었다.
- **phonon → QtMultimedia.** 리소스 뷰어의 사운드 미리듣기(`SoundPlayer`)를 `QMediaPlayer` +
  `QAudioOutput` 으로 이식. 외부 인터페이스는 그대로 유지했다.

### 10.6 자동 변환으로는 절대 안 잡히는, 실제로 깨져 있던 것들
1. **테마 CSS 가 통째로 적용되지 않고 있었다.** `LoaderView.step1` 이
   `setStyleSheet(str(QByteArray))` 를 했는데, PySide(Qt4)에서는 내용이 나왔지만 PySide6 는
   **repr**(`b'QToolTip\n{...'`)을 돌려준다. Qt 가 "Could not parse application stylesheet" 만
   찍고 조용히 무시한다. → `.data().decode("utf-8")`.
2. **런처가 뜨자마자 앱이 그대로 종료됐다.** Qt6 는 **부모가 있는 창을
   `quitOnLastWindowClosed` 계산에 포함하지 않는다.** 런처가 `NoriterMain` 의 자식이라
   스플래시가 닫히고 메인 창이 숨겨지는 순간 Qt 가 "마지막 창이 닫혔다" 고 판단했다.
   → 런처를 부모 없는 독립 창으로 만들고 파이썬 참조만 붙들어 GC 를 막는다 (LoaderView, Menu).
3. **lupa 가 Lua 5.5 로 프리뷰를 돌리고 있었다.** 엔진은 LuaJIT 2.1(Lua 5.1)인데 lupa 2.x 의
   기본 `LuaRuntime` 은 번들된 최신 Lua 다. `collectgarbage('setpause')` 가 5.4+ 에서 사라져
   프리뷰 초기화가 실패했다. → `from lupa.lua51 import LuaRuntime`.
   **프리뷰와 엔진의 Lua 버전은 반드시 맞춰야 한다.**
4. **Qt6 의 `QFontDatabase.addApplicationFont` 는 상대 경로를 열지 못한다**(-1 반환).
   Qt4 에서는 cwd 기준 상대 경로가 통했다. → `os.path.abspath()` + 실패 시 방어.
5. 첫 실행 시 작업폴더(`~/Documents/pini_project`)가 없으면 런처가 `os.listdir` 에서 죽었다.
   macOS 는 개인정보 보호(TCC) 때문에 터미널에서 `QDir.mkpath()` 가 실패할 수 있다.
   → 폴더가 없어도 빈 목록으로 넘어가게 했다.

### 10.7 네이티브 모듈
`scripts/build-editor-natives.sh` 추가. 옛 `Engine/ATL_compile.py` /
`Editor/nativeUtil/native_compile.py` 는 python2 인 데다 인자 배열에 쉼표가 빠져
`-DGPP_FOR_PYTHON=1-E` 가 되는 등 그대로는 동작하지 않는다.
- `atl.so` (arm64) 를 `Editor/pini/` 에 생성. 없으면 **모듈 29개가 import 조차 안 된다.**
- 빌드하면서 `Classes/utils.h` 의 실제 버그를 고쳤다: `GPP_FOR_PYTHON` 빌드에서는 cocos2d.h 를
  포함하지 않아 `CC_TARGET_PLATFORM` 과 `CC_PLATFORM_WIN32` 가 **둘 다 미정의(=0)** 가 되고,
  `0 == 0` 이 참이 되어 mac 에서도 `<windows.h>` 를 포함하려 했다.
- `ATL.cpp` 의 dangling pointer 2건도 수정 (소멸된 임시/스택 객체 주소를 반환하던 곳).
  에디터가 `restype=c_char_p` 로 읽는 함수라 실제 크래시 요인이었다.
- `native.so`(BSP 이미지 패킹)는 **포팅된 코드 어디에서도 로드하지 않아** 기본 빌드에서 뺐다
  (`WITH_NATIVE=1` 로 opt-in). 저장소의 것은 Mach-O 도 아닌 다른 플랫폼 산출물이라 덮어쓰지 않는다.

### 10.8 에디터 → 엔진 실행 연결 (§3.5-7)
- `Menu.__run__` 의 darwin 분기에 **리소스 동기화를 추가**했다. 윈도우 분기는 실행 직전에
  `src`/`res` 를 런타임 폴더로 다시 복사하는데 mac 분기에는 그게 통째로 없어서,
  `Engine/VisNovel/src` 를 고쳐도 .app 안에 구워진 예전 것이 계속 실행됐다.
- 개발 중에는 `scripts/build-mac.sh` 산출물(arm64)이 있으면 그것을 우선 실행한다.
  `Engine/OSX.app` 은 2015년 x86_64 산출물이라 Apple Silicon 에서 Rosetta 가 필요하다.
- `open` → `open -n` (실행 버튼을 다시 누르면 새 인스턴스).

### 10.9 실행(에디터 -> 엔진) 이 실제로 동작하지 않던 이유 — RemoteClient 전면 수정

"프로젝트를 실행하면 금방 꺼진다" 의 원인이 여기였다. **TCP 프로토콜 구현(`command/RemoteClient.py`)이
py3/PySide6 에서 거의 전부 깨져 있었다.**

1. **핵심**: `self.order = str(fin.device().read(4))`.
   `QIODevice.read()` 는 QByteArray 를 돌려주는데, PySide(Qt4)는 `str()` 이 내용을 줬지만
   PySide6 는 **repr** 을 준다 (`"b'PATH'"`, 7글자). 그래서 바로 다음 줄의 `len(self.order) == 4`
   가 항상 거짓이 되고, **엔진에서 PATH 를 받은 직후 파일 전송이 통째로 멈춰** 있었다.
   (스타일시트가 적용되지 않던 것과 완전히 같은 원인이다. `str(QByteArray)` 를 의심할 것.)
2. `payload` 를 `""` 로 시작해 QByteArray 를 더하던 것 → `b""` + `bytes(...)`.
3. `int(fin.device().read(11))` → py3 는 bytes 를 int() 에 넣지 못한다. decode 후 strip.
4. `checksum()` 이 `b64encode(hexdigest())` 로 str 을 넘겨 TypeError.
   엔진 쪽(`src/main.lua`)이 `to_base64(md5.sumhexa(data))` 로 계산하므로 **digest 가 아니라
   hexdigest 를 base64** 해야 한다. 형식을 유지한 채 bytes 경유로 고쳤다.
5. `QByteArray("문자열")` 6곳 → PySide6 는 bytes 만 받는다.
6. `startLine` 4바이트 필드를 `resize(4)` 로 만들었는데 늘어난 부분은 초기화가 보장되지 않는다.
   명시적으로 0 으로 채웠다 (엔진은 `tonumber(recv(input,4))` 로 읽고 NUL 패딩을 허용한다).

수정 후 프로토콜이 완주하는 것을 확인했다:
`PATH` -> 쓰기 경로 수신 -> `flst`(체크섬 목록) -> `ulst`(갱신 대상 67개) -> `tran` 67회 -> `ufin`.

### 10.10 프로세스가 그냥 죽던 원인들 (에러 창 없이 사라짐)
- **SIGABRT**: `CompilingThread`(프리뷰 컴파일 루프)는 에디터 창이 hide 될 때만 멈춘다.
  창이 열린 채 앱이 종료되면 실행 중인 QThread 가 파괴되면서 Qt 가 프로세스를 abort 시킨다
  (`QThread: Destroyed while thread is still running`). → `aboutToQuit` 에서 멈추고 wait.
- 종료 경로에서 예외가 나면 임시저장/정리가 통째로 건너뛰어졌다:
  `getTempFileName()` 이 `self.sceneCtrl` 이 None 인 상태에서 터졌다 (호출부까지 방어 추가).
- `SceneScriptWindowManager.setActive()` 의 `list.remove(view)` 가 ValueError.
  Qt6 에서는 창이 큐에 등록되기 전에 `focusInEvent` 가 먼저 올 수 있다.
- `LineNumberArea` 가 `mousePressEvent` 없이 `mouseMoveEvent` 를 받으면 AttributeError.
- 2to3 의 `fix_next` 가 **Qt 메서드인 `QTextBlock.next()`** 를 파이썬 이터레이터로 착각해
  `next(block)` 으로 바꿔 놨다. 스크립트 에디터가 **매 리페인트마다** 예외를 던졌다 (3곳).
  → `fix_filter` 사고와 같은 유형이다. **`.next()` 를 가진 Qt 타입을 조심할 것.**
- `QPropertyAnimation(v, "pos")` → PySide6 는 프로퍼티 이름을 bytes 로 받는다.
- Qt6 에서 제거된 `QImage.alphaChannel()` → 알파 있는 포맷으로 변환.

수정 후 전체 시나리오(프로젝트 열기 -> 실행 -> 엔진 기동 -> 파일 동기화 -> 씬 시작 -> 종료)가
**예외 0건, 종료코드 0** 으로 통과한다.

### 10.11 WYSIWYG 미리보기가 비어 보이던 이유
`QPainter.HighQualityAntialiasing` 은 Qt6 에서 **제거**되었다 (Qt5.14 부터 deprecated 였고
Antialiasing 과 동일하게 취급됐다). 미리보기 아이템들의 `paint()` 가 이걸 참조해서
**매 프레임 예외로 죽었고**(로그에 1726회), 그래서 장면 객체는 정상적으로 만들어지는데도
화면에는 아무것도 안 그려졌다. → `QPainter.Antialiasing` 으로 교체 (4곳).

확인 방법 메모: 미리보기는 **커서가 있는 줄까지의 상태**를 그린다. 커서가 1번째 줄에 있으면
아무것도 안 나오는 게 정상이므로, 디버깅할 때 커서 위치를 먼저 확인할 것.
(자동 검증에서는 커서를 21행으로 옮긴 뒤 씬을 QImage 로 렌더해 배경/캐릭터/이름표/대사가
모두 그려지는 것을 확인했다.)

이런 "Qt6 에서 사라진 상수/속성" 을 한 번에 훑으려면 소스의 `Q어떤클래스.속성` 을 전부 뽑아
PySide6 에 실제로 존재하는지 `hasattr` 로 확인하면 된다. 지금은 남은 것이 없다.

### 10.12 "테스트 실행" 이 아무 반응도 없던 이유 — 두 가지가 겹쳐 있었다

**(1) LuaJIT 2.0 -> 2.1 로 올리면서 Lua 5.0 시절 별칭이 사라졌다 (§9.3 의 여파)**
엔진 Lua 는 2015년 LuaJIT 2.0 기준으로 작성되어 `math.mod`, `table.getn` 을 쓴다.
**LuaJIT 2.1 은 이 별칭들을 제거했다.** (Lua 5.1 과 LuaJIT 2.0 에는 있다.)
- `src/base64.lua` 의 `to_base64()` 가 `math.mod` 에서 죽는다.
  그래서 엔진이 에디터의 **`flst`(파일 체크섬 목록) 요청에 응답하지 못하고 `ulst` 를 보내지
  않는다.** 에디터는 응답을 기다리며 멈추고, 사용자 눈에는 "실행해도 아무 일도 안 남" 으로 보인다.
- `table.getn` 은 PiniAPI 의 터치 처리와 vendored cocos lua 프레임워크에서 29곳 쓰인다.

호출부 29곳을 고치는 대신 **엔진 진입점(`src/main.lua`) 맨 위에 호환 shim** 을 넣었다
(없을 때만 정의하므로 Lua 5.1 / LuaJIT 2.0 에서는 no-op).
에디터 프리뷰는 lupa 의 Lua 5.1 을 쓰는데 거기엔 이 함수들이 살아 있어 영향이 없다.

> **다음에 Lua VM 을 건드릴 때 반드시 확인할 것:** 런타임을 바꾸면 표준 라이브러리에서
> 조용히 사라지는 함수가 있다. 엔진과 에디터 프리뷰가 서로 다른 Lua 를 쓰고 있어서
> "에디터에서는 되는데 엔진에서만 안 되는" 형태로 나타난다.

**(2) 엔진과 에디터가 서로 다른 폴더를 보고 있었다**
- cocos 의 mac 기본 쓰기 경로는 `~/Documents/` 다 (`CCFileUtils-apple.mm`).
  macOS 는 이 폴더를 개인정보 보호(TCC)로 막기 때문에 파일 쓰기가 조용히 실패할 수 있다.
- 반면 에디터는 `appdirs.user_data_dir("pini_remote")` =
  `~/Library/Application Support/pini_remote` 에 빌드 산출물을 복사한다.
→ `AppDelegate::applicationDidFinishLaunching` 맨 앞에서 mac 일 때만
  `FileUtils::setWritablePath()` 로 Application Support 를 지정해 둘을 일치시켰다.
  (cocos 를 고치지 않고 게임 코드에서 해결. iOS 는 샌드박스 안 `~/Documents` 가 정상이므로 그대로 둔다.)

검증: `PATH` -> `flst` -> `ulst` -> `tran` -> `ufin` 이 완주하고 엔진이 씬을 시작한다.

디버깅 메모: 엔진은 stdout 을 자체 콘솔 창으로 리디렉션해서 터미널에서는 로그가 안 보인다.
Lua 쪽을 파고들어야 하면 `src/main.lua` 에 임시로 파일 로깅(`io.open("/tmp/...","a")`)을
넣는 게 가장 빠르다. `-write-debug-log` 옵션은 거의 아무것도 남기지 않는다.

### 10.13 검은 화면 — 엔진이 씬 파일명을 cp949 기준으로 하드코딩하고 있었다

증상: 엔진 창은 뜨는데 완전히 검은 화면. "저장된 파일 실행하기" 를 눌러도 마찬가지.

원인: 씬 파일 이름은 에디터가 **"원본 파일명을 base64"** 로 만드는데
(`ProjectController.fileNameMD`), base64 하기 전 인코딩 기준이 시기마다 달랐다.
- py2 / 윈도우 에디터: **cp949** → `"메인"` = `lnx_uN7Azg__`
- py3 포팅 이후(§10.4 에서 utf-8 로 통일): **utf-8** → `"메인"` = `lnx_66mU7J24`

그런데 엔진 `src/main.lua` 가 **cp949 쪽 이름을 하드코딩**하고 있었다 (3곳):
- `LanX_start("scene/lnx_uN7Azg__")` — "저장된 파일 실행하기" 버튼
- 같은 호출 — 시작 시 자동 실행
- `XVM:call("scene/lnx_x8G4rrjewM4_")` — "프리메인.lnx" (선택 사항 씬)

→ py3 에디터가 만든 프로젝트에서는 씬을 영영 못 찾는다. 게다가 프리메인 쪽은 **존재 확인 없이**
호출해서, 파일이 없으면(샘플 프로젝트 포함 대부분) `require` 예외가 `LanX_start` 의 try 블록을
통째로 중단시켰다. 그래서 **본편 씬이 시작조차 못 하고 검은 화면**이 됐다.

수정: `resolveSceneName()` 헬퍼를 두고 utf-8 이름 → cp949 이름 순으로 **실제 존재하는 것**을
고르게 했다. 프리메인은 없으면 조용히 건너뛴다. 이러면 py3 로 만든 새 프로젝트와 윈도우 시절의
기존 프로젝트가 모두 동작한다.

> 파일명 인코딩을 utf-8 로 통일한 결정(§10.4)은 **에디터 안에서 끝나지 않는다.**
> 엔진이 그 이름을 읽는 모든 지점을 같이 봐야 한다. 안드로이드/윈도우 런타임에도
> 같은 하드코딩이 있는지 Phase 4 에서 확인할 것.

부수적으로 `ufin` 의 startLine 4바이트 필드를 NUL 로 패딩하면 안 된다는 것도 여기서 드러났다:
**LuaJIT 2.1 의 `tonumber("0\0\0\0")` 는 nil** 이다 (Lua 5.1 은 0 을 돌려준다).
nil 이 되면 바로 다음 줄의 문자열 연결에서 죽어 역시 검은 화면이 된다.
→ 에디터는 공백으로 패딩하고, 엔진은 패딩을 걷어낸 뒤 숫자가 아니면 0 으로 보게 했다.

디버깅 메모: 엔진 Lua 의 에러를 보려면 `src/main.lua` 맨 위에서 `print` 를 후킹해
파일로 남기는 방법이 가장 빠르다. 엔진은 stdout 을 자체 콘솔 창으로 리디렉션하기 때문에
터미널에서는 아무것도 안 보이고, `-write-debug-log` 도 거의 남기지 않는다.

### 10.14 남은 것 / 알려진 제약
- **`--fullscreen` 이 mac 에서 동작하지 않는다.** 엔진 mac 타겟이 인자를 읽지 않는다
  (`AppDelegate(bool fullscreen = false)` 기본값 고정). 지원하려면 `mac/SimulatorApp.mm` 에서
  인자를 파싱해 `new AppDelegate(fullscreen)` 으로 넘겨야 한다.
- `Engine/OSX.app` 은 **arm64 런타임으로 교체 완료** (`scripts/install-mac-runtime.sh`).
  기존에 들어 있던 2015년 x86_64 산출물("novel Mac")은 대체되었다.
- **Windows 익스포트 경로(`Export_Windows.py` / `Export_Android.py`)는 문법만 py3 로 바꿨고
  동작 검증은 하지 않았다.** `pepy`(PE 아이콘 교체)는 win32 가드 안으로 옮겼다 — 현대 Pillow
  에서 삭제된 `PIL._binary` 를 쓰므로 Windows 에서도 손을 봐야 한다. (Phase 5 과제)
- `clone.py` 는 `gittle`(py2 시절 git 라이브러리)에 의존해 import 되지 않는다. 에디터 어디에서도
  쓰지 않는다. `updator/` 폐기와 함께 정리 대상.
- `exec_()` 36곳은 PySide6 6.11 에서 아직 동작하지만 deprecated 다. 다만 `Export_Windows` 의
  `EditWindow` 가 `exec_` 를 **오버라이드**하고 있어, 일괄 치환하면 오버라이드가 끊긴다.
  바꿀 때는 정의부와 호출부를 같이 고칠 것.
- Retina 에서의 좌표 계산(정수 나눗셈이 py3 에서 true division 이 된 곳)은 실제 GUI 조작 중
  드러날 수 있다. 현재까지 구동/컴파일 경로에서는 문제가 없었다.


## 11. Phase 3 수행 결과 — iOS arm64 (2026-07-26)

### 11.1 결과
`pini_remote-mobile.app` 이 **arm64 실기기용으로 서명 없이 빌드된다** (minos 15.0 / SDK 26.2).
비-시스템 동적 의존성 없음.

```
scripts/build-ios.sh          # 앱 전체 (Release, 서명 없음)
scripts/build-ios.sh "libcocos2d iOS"   # 특정 타겟만
```
산출물: `.../proj.ios_mac/build/Release-iphoneos/pini_remote-mobile.app`

시뮬레이터는 여전히 불가능하다 (§4.2: cocos 의 iOS 프리빌트에 arm64 시뮬레이터 슬라이스가 없다).

### 11.2 사전조사(§4.4) 대비 정정 — **예상보다 훨씬 쉬웠다**
- **UIWebView / MPMoviePlayerController 는 그냥 컴파일된다.** §4.4-5,6 은 "SDK에서 제거된 API라
  컴파일 실패" 로 봤지만, iOS 26.2 SDK 는 여전히 deprecated 상태로 선언을 유지하고 있어
  `UIWebView.mm`, `UIWebViewImpl-ios.mm`, `UIVideoPlayer-ios.mm` 모두 문제없이 빌드된다.
  → 빌드를 위해 cocos 소스를 들어낼 필요가 없었다. **다만 앱스토어 제출 시에는 여전히
  걸림돌이다 (§11.5 참조).**
- cocos2d-x 본체(856파일)와 lua-bindings, libsimulator 모두 **소스 수정 0건**으로 iOS arm64 빌드 성공.
  Phase 1 에서 mac 용으로 고친 것들(audio shim, iconv 캐스팅, glfw/chipmunk 대응)이 그대로 통했다.

### 11.3 실제로 막혔던 것 — Phase 1 의 여파 하나
링크 단계에서 미해결 심볼이 **`_luaL_setfuncs` 하나** 나왔다.

원인: `external/chipmunk/include` 와 `external/lua/luajit/include` 는 **전 플랫폼 공용 디렉토리**다.
Phase 1 에서 mac 용으로 이 헤더들을 chipmunk 7.0.3 / LuaJIT 2.1 로 갱신했는데,
iOS 프리빌트는 2016년산(chipmunk 7.0.1 / LuaJIT 2.0) 그대로였다.
LuaJIT 2.0 에는 `luaL_setfuncs` 가 없어서 헤더(2.1)와 라이브러리(2.0)가 어긋난 것이다.

→ `scripts/build-deps-apple.sh` 에 **iOS 모드**를 추가해 이 둘을 iOS arm64 로 다시 만들었다:
```
PLATFORM=ios scripts/build-deps-apple.sh chipmunk luajit
```
- 헤더가 공용이므로 헤더 갱신은 mac 빌드 때만 한다 (스크립트가 알아서 구분).
- LuaJIT iOS 는 크로스 컴파일이고 JIT 없이 인터프리터로 동작한다 (iOS 는 W^X 때문에 정상).
- **다른 라이브러리(png/jpeg/tiff/webp/freetype/websockets/curl/openssl)는 건드릴 필요가 없다.**
  `include/ios` 를 따로 갖고 있어서 2016년산 프리빌트와 짝이 맞기 때문이다.

> 교훈: `external/<lib>/include` 아래에 플랫폼 디렉토리가 없는 라이브러리는 헤더가 공용이다.
> 한 플랫폼에서 버전을 올리면 **모든 플랫폼의 프리빌트를 같이 올려야 한다.**
> 지금 공용인 것은 chipmunk 와 lua/luajit 둘뿐이다. (Android 도 Phase 4 에서 같은 처리가 필요하다.)

### 11.4 프로젝트/번들 정리
- `IPHONEOS_DEPLOYMENT_TARGET` 6.0 → **15.0** (프로젝트 레벨 + iOS 타겟).
- `VALID_ARCHS = "arm64 armv7"` → `ARCHS = arm64`. (VALID_ARCHS 는 Xcode 12 부터 폐기된 설정이고
  armv7 은 현행 SDK 가 지원하지 않는다.)
- 존재하지 않는 옛 SDK 절대경로 참조 8건 정리: `iPhoneOS7.0/7.1/8.0/8.1/8.4/9.3.sdk/...` →
  `SDKROOT` 상대경로. `libiconv.dylib` → `libiconv.tbd`.
  (Xcode 가 이름으로 찾아 주긴 했지만 GUI 에서 빨갛게 뜨고 다음 사람이 헷갈린다.)
- `Info.plist`:
  - `UIRequiredDeviceCapabilities` 의 **`opengles-1` → `opengles-2`**. 엔진은 GLES2 렌더러를
    쓰는데 ES1.1 을 요구한다고 선언하고 있었다 (최신 기기 설치 차단 / 스토어 거부 사유).
  - **`UILaunchStoryboardName` + `ios/LaunchScreen.storyboard` 신설.** 스토리보드가 없으면
    iOS 가 최신 기기에서 앱을 레터박스로 축소해 띄우고 제출도 거부된다.
  - 제출에 필요한 `CFBundleShortVersionString` 추가.
- 서브프로젝트 3개의 `SDKROOT = iphoneos11.0` 하드코딩은 mac 과 같은 방식으로
  `scripts/build-ios.sh` 의 커맨드라인 오버라이드로 처리했다 (vendored 프로젝트 파일 수정 최소화).

### 11.5 UIWebView → WKWebView 이식 (앱스토어 거부 사유 제거)

UIWebView 는 iOS 12 에서 deprecated 되었고, **이걸 참조하는 바이너리는 앱스토어가 거부한다
(ITMS-90809).** SDK 에 아직 선언이 남아 있어 빌드는 되지만 제출이 막힌다.

처음에는 "게임이 안 쓰니 cocos 빌드에서 소스를 들어내자" 고 계획했지만(§6 Phase 3-2),
**WKWebView 로 이식하는 쪽이 더 낫고 덜 침습적이었다.**
소스를 들어내면 lua-bindings 의 webview auto/manual 파일과 `lua_module_register` 등록까지
줄줄이 손봐야 하는데, 구현만 갈아 끼우면 **cocos 의 API 표면이 그대로**라 그럴 필요가 없다.
기능도 그대로 남는다.

UIKit 의 `UIWebView` 를 실제로 쓰는 곳은 `cocos/ui/UIWebViewImpl-ios.mm` **한 파일뿐**이었다
(다른 파일의 "UIWebView" 는 cocos 자체 클래스/파일 이름이다).

바뀐 것:
| UIWebView | WKWebView |
|---|---|
| `UIWebViewDelegate` | `WKNavigationDelegate` |
| `shouldStartLoadWithRequest:` (BOOL 반환) | `decidePolicyForNavigationAction:decisionHandler:` |
| `webViewDidFinishLoad:` | `didFinishNavigation:` |
| `didFailLoadWithError:` | `didFailNavigation:` + `didFailProvisionalNavigation:` (둘로 나뉨) |
| `stringByEvaluatingJavaScriptFromString:` (동기, 결과 반환) | `evaluateJavaScript:completionHandler:` (비동기) |
| `loadData:...textEncodingName:` | `loadData:...characterEncodingName:` |
| `scalesPageToFit` 프로퍼티 | 없음 → 로드 완료 후 viewport meta 주입으로 대체 |

- 동기 → 비동기 JS 평가는 문제되지 않는다. cocos 의 `WebView::evaluateJS()` 는 반환값이 void 다.
- 래퍼 클래스 이름도 `UIWebViewWrapper` → `WKWebViewWrapper` 로 바꿨다 (이제 WKWebView 를 감싼다).
- 앱 타겟에 **`WebKit.framework` 링크 추가**.

검증: iOS 바이너리에서 `UIWebView` 참조가 **완전히 0** 이다
(`nm -m | grep _OBJC_CLASS_$_UIWebView` = 0, `strings | grep UIWebView` = 0).
mac 빌드/런타임 회귀 없음.

> 실기기에서 웹뷰 동작 자체는 검증하지 못했다 (게임이 웹뷰를 쓰지 않아 실행 경로에 안 걸린다).
> 웹뷰를 실제로 쓰게 되면 스크롤/투명 배경/JS 콜백 스킴을 기기에서 확인할 것.

### 11.6 남은 것 / 앱스토어 제출 전 필수 작업
- `cocos/ui/UIVideoPlayer-ios.mm` 의 **MPMoviePlayerController** 는 그대로 두었다.
  deprecated 이지만 UIWebView 처럼 자동 거부 대상은 아니다. 게임은 이 위젯을 쓰지 않는다
  (게임의 비디오는 `VideoPlayer_iOS.cpp` 스텁). 필요해지면 AVPlayer 로 이식할 것.
- **서명/프로비저닝.** 실제 `.ipa` 서명과 설치·제출은 사용자 Apple 계정이 필요하다.
  현재 프로젝트에는 `DEVELOPMENT_TEAM = A7E8XURC34` 가 남아 있다 (2015년 팀 ID로 보인다).
- **아이콘/런치 이미지 현대화.** 지금은 개별 PNG 목록(`CFBundleIconFiles`) 방식이다.
  최신 방식은 Asset Catalog(`AppIcon`)이며, 제출 시 1024x1024 마케팅 아이콘이 필요하다.
- **시뮬레이터 지원.** arm64 시뮬레이터 슬라이스가 없어 불가능하다. 필요하면 §4.7-5 대로
  의존성을 iOS-simulator 까지 빌드해 xcframework 로 묶어야 한다.
- 실기기에서의 **동작 검증은 아직 못 했다.** 빌드까지만 확인했다.
  (에디터 ↔ 엔진 TCP 는 mac 에서 검증했고 프로토콜은 플랫폼 중립이다.)

---

# 12. Phase 4 (Android) 진행 결과

**결론: `./gradlew assembleDebug` 로 arm64-v8a 를 포함한 APK 생성에 성공했다 (성공 기준 충족).**

```
build/outputs/apk/debug/pini_remote-debug.apk        25 MB
  └ lib/arm64-v8a/libcocos2dlua.so                   20 MB  ELF 64-bit, ARM aarch64
  └ assets/                                          127 개 (src/ + res/ + config.json)
  └ classes.dex ~ classes5.dex
```

빌드 방법:

```sh
cd Engine/VisNovel/frameworks/runtime-src/proj.android
./gradlew assembleDebug
```

사전에 `scripts/build-deps-android.sh` 로 네이티브 의존성이 준비돼 있어야 한다 (§12.2).

## 12.1 빌드 시스템: ant → Gradle (AGP 8.6 + ndk-build)

`proj.android` 는 ant(`build.xml`) 프로젝트였고 `proj.android-studio` 는 **게임 코드가 없는
cocos 순정 템플릿**이었다(§5.1). 둘 중 하나를 고르는 대신 **ant 레이아웃을 그대로 둔 채
Gradle 을 얹었다.** 소스를 복제하지 않아 진실의 출처가 하나로 유지된다.
`proj.android-studio` 는 손대지 않았다.

새로 추가한 파일: `build.gradle`, `settings.gradle`, `gradle.properties`,
`gradlew`/`gradlew.bat`/`gradle/wrapper/` (Gradle 8.9).

`build.gradle` 의 핵심은 **ant 디렉터리 배치를 sourceSets 로 그대로 선언**하는 것이다
(`java.srcDirs = ['src', ...]`, `manifest.srcFile 'AndroidManifest.xml'`, `res.srcDirs = ['res']`).

- `namespace` / `applicationId` = `com.nooslab.pini_remote_landscape`, compileSdk 35,
  minSdk 24, targetSdk 35, ndkVersion 27.1.12297006
- 네이티브는 **기존 `jni/Android.mk` 를 `externalNativeBuild.ndkBuild` 로 그대로** 쓴다.
  cocos 3.15 는 CMake 지원이 부실해서 ndk-build 가 최단 경로다.
- `arguments "NDK_MODULE_PATH=..."` — cocos 의 `Android.mk` 들이 `import-module` 로 서로를
  찾는 데 필요하다. 예전에는 cocos 콘솔이 주입해 주던 값이다.
- `abiFilters 'arm64-v8a'` — `Application.mk` 는 `armeabi-v7a` 도 열어 뒀지만 현재 검증한 건
  arm64 뿐이라 Gradle 에서 좁혔다 (§12.7).
- `jniLibs.srcDirs = []` — `libs/` 의 폐기된 광고 SDK jar 와 32bit `armeabi` `.so` 를 끌어오지
  않기 위해서다. 네이티브는 `externalNativeBuild` 산출물만 쓴다.

### ndk-build 모듈명

AGP 는 매니페스트의 `android.app.lib_name`(=`cocos2dlua`)을 **ndk-build 의 make 타겟**으로
넘긴다. 기존 모듈명은 `cocos2dlua_shared` + `LOCAL_MODULE_FILENAME := libcocos2dlua` 조합이라
`No rule to make target 'cocos2dlua'` 로 실패했다. 모듈명을 산출물 파일명과 일치시켰다
(`LOCAL_MODULE := cocos2dlua`, `LOCAL_MODULE_FILENAME` 삭제).

### `Application.mk`

- `APP_STL`: `gnustl_static` → **`c++_static`** (NDK r18 부터 gnustl 제거)
- `APP_ABI`: 미지정(=cocos 기본값 `armeabi`) → **`arm64-v8a armeabi-v7a`**.
  플레이스토어는 2019년부터 64bit 를 필수로 요구한다.
- `APP_PLATFORM := android-24`, `-std=c++14`
- `APP_CFLAGS += -Wno-implicit-const-int-float-conversion` — cocos 가 vendored 한
  pvmp3dec(MP3 디코더)가 자체 `Android.mk` 에서 `-Werror` 를 켜는데, 최신 clang 이 새로 추가한
  경고 때문에 **의도된** 고정소수점 상수 계산이 에러로 승격된다.

## 12.2 네이티브 의존성 재빌드 (`scripts/build-deps-android.sh`)

저장소의 안드로이드 프리빌트는 2016년산 `armeabi`/`armeabi-v7a` 위주라 arm64 를 못 만든다.
mac/iOS 와 같은 방식으로 소스에서 다시 빌드한다.

| 라이브러리 | 비고 |
|---|---|
| LuaJIT 2.1 | **Phase 1 에서 헤더를 2.1 로 올렸으므로 필수.** 2.0 프리빌트와 섞으면 `_luaL_setfuncs` undefined (§11 iOS 와 동일한 함정) |
| chipmunk 7.0.3 | `sys/sysctl.h` 를 `__ANDROID__` 에서 가드 |
| libwebsockets | SSL 없이 |
| openssl 1.1.1w | 아래 참조 |

**openssl 을 걷어낼 수 없는 이유.** 2016년 arm64 프리빌트가 있긴 한데 **non-PIC** 라 최신
lld 가 거부한다. cocos 의 `curl` 이 https 에 openssl 을 쓰므로 제거도 불가능해서,
`-fPIC` 로 1.1.1w 를 다시 빌드했다.

**LuaJIT 가 Mach-O 로 나오던 문제.** mac 빌드가 남긴 오브젝트가 공유 소스 트리에 남아 있는데
LuaJIT 의 `make clean` 이 이를 완전히 지우지 못한다. ABI 마다 `git archive HEAD | tar -x` 로
**깨끗한 트리를 새로 펼쳐** 빌드하고, 산출물이 ELF 인지 검증하도록 했다.

## 12.3 Java 축소: `AppActivity.java` 850줄 → 223줄

2015년 앱이라 죽은 SDK 가 잔뜩 붙어 있었다. 광고 SDK 4종, Fabric/Crashlytics,
OBB 확장파일 다운로더, AIDL v3 인앱결제를 걷어냈다. 원본은 `AppActivity.java.orig-ant` 로 남겨 뒀다.

**중요 — Lua 가 부르는 static 메서드 16개는 시그니처를 그대로 유지했다.** Lua 쪽은 JNI 로
이름/시그니처를 찾으므로 하나라도 없으면 런타임에 죽는다.

**더 중요 — 스텁도 반드시 콜백해야 한다.** 결제·OBB 호출부의 Lua 는 `vm:stop()` 으로 코루틴을
세우고 콜백을 기다린다. 콜백이 영영 안 오면 스크립트가 그 자리에서 **영구 정지**한다.
그래서 스텁은 즉시 실패/성공을 돌려준다:

- `IAB_*` → `CallLua("PINI_IAP_CALLBACK", "{\"result\":false}")`
- `ExtensionFile_Download` → `CallLua("PINI_OBB_DOWNLOAD_RESULT", "1")`
- `ExtensionFile_IsFileExists` → `true` (확장파일 없이 APK 내장 리소스로 동작)

삭제: `ExpansionFileAlarmReceiver.java`, `ExpansionFileDownloaderService.java`.

## 12.4 `AlarmReceive.java` (로컬 알림)

`new Notification(icon, tickerText, when)` + `setLatestEventInfo()` 는 **API 11 에서 폐기,
API 23 에서 제거**됐다. `NotificationCompat.Builder` + `NotificationChannel`(API 26+) 로
재작성하고, `PendingIntent` 에 `FLAG_IMMUTABLE` 을 붙였다 (API 31+ 필수).

## 12.5 `AndroidManifest.xml`

- `package` 속성 제거 — AGP 8 은 `namespace` 를 쓰고, 남아 있으면 빌드가 실패한다
- `<uses-sdk>` 제거 — `build.gradle` 로 이동
- 모든 액티비티/리시버/서비스에 `android:exported` 명시 (API 31+ 필수)
- 광고/Fabric/확장파일/결제 권한과 컴포넌트 제거

## 12.6 cocos 자바 런타임 쪽에서 걸린 것들

cocos 소스를 최대한 안 고치는 방향으로 풀었다.

| 증상 | 원인 | 조치 |
|---|---|---|
| `com.android.vending.expansion.zipfile` 없음 | `Cocos2dxHelper` 가 OBB zip 읽기를 참조 | **저장소에 이미 있는** `android-extension/play_apk_expansion/zip_file/src` 를 `java.srcDirs` 에 추가 |
| `com.enhance.gameservice` 없음 | `IGameTuningService` 는 AIDL | `aidl.srcDirs` 지정 + `buildFeatures { aidl true }` (AGP 8 부터 기본 꺼짐) |
| `com.loopj.android.http` 없음 | `Cocos2dxDownloader` 의 async-http. 기존 `libs/` jar 는 API 23 에서 빠진 Apache HttpClient 의존 | Maven `com.loopj.android:android-async-http:1.4.9` (HttpClient 를 `cz.msebera` 로 리패키징해 내장) |
| `com.android.vending.billing` 없음 | AIDL v3 결제 헬퍼 `com.android.util.Iab*` | `java.exclude '**/com/android/util/**'` (§12.7) |
| `org.cocos2dx.enginedata` 없음 | **저장소에 인터페이스 파일 자체가 없다.** OEM 성능 힌트 연동 | `Cocos2dxEngineDataManager.java` 를 no-op 스텁으로 교체. 원본은 `.orig` 보관 |

## 12.7 리소스 동기화 (`syncGameAssets`)

예전에는 `cocos compile` 이 `build-cfg.json` 의 `copy_resources` 를 읽어
`src`/`res`/`config.json` 을 `proj.android/assets/` 로 복사했다. 그 복사본이 저장소에
커밋돼 있는데 **정작 `src/`(Lua 전체)가 빠져 있다.** 그대로 패키징하면 APK 는 만들어지지만
엔진이 `src/main.lua` 를 못 찾아 즉시 죽는다 — 빌드 성공만 보고 넘어가기 쉬운 함정이다.

그래서 assets 를 **원본에서 빌드 때마다 동기화하는 생성 디렉터리**
(`build/generated/pini-assets`)로 바꿨다. `Sync` 태스크가 `build-cfg.json` 과 같은 일을 하고,
`merge*Assets` 가 여기에 의존한다. 복사본이 원본과 어긋날 여지가 없어진다.

> `proj.android/assets/` (커밋된 54개 파일)는 이제 **쓰이지 않는 잔재**다.
> 정리 여부는 사용자 판단에 맡기고 건드리지 않았다.

## 12.8 남은 과제

- **실기기 동작 검증을 아직 못 했다.** 빌드와 APK 내용물 확인까지만 했다.
- **`armeabi-v7a`.** `Application.mk` 에는 열려 있지만 의존성 빌드/링크를 검증하지 않아
  `abiFilters` 로 막아 뒀다. 32bit 를 지원하려면 §12.2 를 v7a 로도 돌리고 풀면 된다.
- **인앱결제.** AIDL v3 는 폐기됐다. Play Billing 7+ 로 재작성해야 실제 결제가 된다.
  그 전까지는 실패 콜백 스텁이다.
- **비디오 재생.** ffmpeg 프리빌트가 `armeabi` 뿐이라 `VideoPlayer_iOS` no-op 스텁을 쓴다
  (§4.5, §5.3). 안드로이드는 `MediaPlayer`/`ExoPlayer` 로 다시 붙이는 게 맞다.
- **서명.** 현재는 debug 서명이다. release 는 §5.5 (커밋된 keystore) 결론이 먼저 필요하다.
- `local.properties` 는 머신마다 다른 SDK 경로라 추적에서 뺐다 (`.gitignore` 추가).
  파일 자체는 "must *NOT* be checked into Version Control Systems" 라고 스스로 명시하고 있다.

---

# 13. Phase 5 (익스포트 파이프라인) — iOS

**결론: 에디터 `파일 > 익스포트 > iOS...` 로 `.ipa` 를 만들 수 있다.**
서명 없이 아카이브까지 도는 것은 검증했다(리소스 주입·Info.plist 치환·arm64 확인).
`.ipa` 추출은 Apple 팀 ID 가 필요해서 검증하지 못했다.

원본 에디터에는 **iOS 익스포트가 처음부터 없었다** (윈도우/안드로이드 둘뿐).
Windows 전용 도구로 만들어졌기 때문이다.

## 13.1 왜 로직을 스크립트로 뺐나

`Export_Windows.py`(775줄)와 `Export_Android.py`(1,223줄)는 도구 호출을 파이썬 안에
직접 박아 놨다 — `luac.exe`, `7z.exe`, `jarsigner.exe`, `makensis.exe`, `adb.exe`.
그래서 windows 도구체인에 묶여 mac 에서는 통째로 못 쓴다.

같은 전철을 밟지 않도록 iOS 는 빌드 로직을 **`scripts/export-ios.sh`** 에 두고
에디터는 (1) 리소스 스테이징, (2) 스크립트 실행과 로그 표시만 한다.
에디터 없이 커맨드라인/CI 에서도 그대로 돌릴 수 있다.

## 13.2 리소스 주입 — 저장소를 건드리지 않는 방법

Xcode 프로젝트에서 `src`/`res` 는 `../../../src`, `../../../res` 를 가리키는
**폴더 참조**다(`lastKnownFileType = folder`). 즉 빌드 시점에 그 경로에 있는 것이
통째로 번들된다. 게임마다 다른 내용을 넣겠다고 `Engine/VisNovel/src` 를 덮어쓰면
에디터의 개발·미리보기 워크플로가 깨진다.

그래서 `pini_remote-mobile` 타겟에 **"Pini export stage"** 빌드 페이즈를 추가했다.
`PINI_EXPORT_STAGE` 빌드 설정이 지정됐을 때만 번들 안의 `src`/`res` 를 스테이징
내용으로 갈아끼우고, 지정되지 않으면 아무 일도 하지 않는다. 평소 빌드는 영향이 없다.

스크립트는 아카이브 후 번들에 `_export_execute_.lua` 가 있는지 확인한다.
주입이 조용히 실패하면 **엉뚱한 게임(또는 원격 모드)이 담긴 앱**이 나오는데,
빌드는 성공하므로 알아채기 어렵다.

## 13.3 공유 스킴 추가

`xcodebuild` 의 `archive` 액션은 `-target` 이 아니라 `-scheme` 을 요구한다.
기존 스킴은 자동 생성본이라 `xcuserdata/`(머신별) 아래에만 있어서 다른 환경에서는
재현되지 않는다. `xcshareddata/xcschemes/pini_remote-mobile.xcscheme` 를 저장소에 넣었다.

## 13.4 Info.plist

`ios/Info.plist` 는 번들 ID 가 `com.p.p` 로 하드코딩돼 있고 버전도 고정이다.
저장소 파일을 고치는 대신 **스테이징에 복사해서 PlistBuddy 로 수정**하고
`INFOPLIST_FILE` 로 그 경로를 넘긴다.

## 13.5 스테이징 순서

`Export_Windows` 와 같게 맞췄다. 프로젝트 컴파일 결과(`<project>/build/`)를 먼저 깔고
그 위에 엔진 기본 `src`/`res` 를 덮는다(엔진 쪽이 우선). `.obj` 는 제외한다.
마지막에 `_export_execute_.lua` 를 쓴다 — 이 파일이 없으면 런타임이 원격 모드로 뜬다.

## 13.6 입력 검증

번들 ID 를 정규식으로 먼저 거른다. 안 그러면 **10~20분짜리 아카이브가 끝난 뒤에야**
xcodebuild 가 거부한다. Xcode 설치 여부와 iOS 프로젝트 존재도 창을 열 때 확인한다.

## 13.7 남은 과제

- **`.ipa` 추출 경로는 미검증.** Apple 팀 ID 가 있어야 돌려볼 수 있다.
- **앱 아이콘 교체 미지원.** 현재는 저장소의 `Icon-*.png` 가 그대로 들어간다.
  최신 방식은 Asset Catalog 이며 제출에는 1024x1024 마케팅 아이콘이 필요하다(§11).
- **리소스 암호화(`res.prz`) 미지원.** 윈도우 익스포트는 `7z.exe` 로 한다.
  mac 에서는 파이썬 `zipfile` 이나 `ditto` 로 다시 만들어야 한다.
- **안드로이드 익스포트는 여전히 Windows 전용이다.** Phase 4 에서 Gradle 빌드는
  올렸으니, `Export_Android.py` 를 `./gradlew assembleRelease` 호출로 바꾸면
  같은 구조로 정리할 수 있다.

---

# 14. 커밋된 비밀 처리 (§5.5 결론)

사용자 판단: **새 키를 발급하고 기존 것은 이력에서 제거한다.**

## 14.1 왜 교체가 유일한 해결책인가

`piniremote.keystore` 는 평문 비밀번호(`ant.properties`: `02881212`)와 함께 공개
저장소에 있었다. **파일과 비밀번호가 모두 노출된 서명키는 되돌릴 수 없이 손상된 것**이다.
제3자가 같은 키로 서명한 APK 를 만들 수 있다. 이력에서 지워도 이미 클론·포크한 사본은
회수할 수 없다.

이력 정리 중에 **`test_keystore/`** 도 발견했다. 별도 keystore(`com.n.a12`)와
비밀번호가 적힌 `정보.txt` 가 같이 들어 있었다. 함께 제거 대상에 넣었다.

## 14.2 한 일

- `scripts/make-release-keystore.sh` — 새 키 발급. PKCS12/RSA 4096/30년.
  커밋하지 않는 `keystore.properties` 를 함께 생성한다.
- `build.gradle` 에 `signingConfigs.release` 추가. `keystore.properties` 또는
  `PINI_KEYSTORE*` 환경변수에서 읽는다. **설정이 없으면 signingConfig 를 아예 만들지
  않아** debug 빌드는 키 없이도 그대로 된다. release 를 서명 없이 돌리면 경고를 띄운다.
- 세 파일을 추적 해제하고 `.gitignore` 에 `*.keystore`, `*.jks`, `keystore.properties`
  등을 추가했다. **파일 자체는 디스크에 남겼다** — 구 키 보관본이다.
- `git-filter-repo` 1차 실행으로 `Engine/` 경로의 세 파일과 Fabric API key/secret
  문자열을 제거했다.

## 14.3 아직 안 끝났다

프로젝트가 예전에 `novel/` 아래 있다가 `Engine/` 으로 옮겨져서, **`novel/` 시절 경로에
사본이 남아 있다.** `test_keystore/` 도 그대로다. 나머지는
**`scripts/purge-secrets-history.sh`** 로 처리한다.

```sh
scripts/purge-secrets-history.sh
```

백업:

```
~/projects/pini-engine-backup-20260726.bundle          # 전체 이력 (642MB)
~/projects/pini-engine-backup-20260726-secrets/        # 구 keystore 사본
```

복구는 `git clone pini-engine-backup-20260726.bundle`.

## 14.4 원격 반영은 별도 결정이다

이력을 다시 쓰면 **모든 커밋 SHA 가 바뀐다.** 원격에 반영하려면 force push 가 필요하고,
이건 되돌릴 수 없다.

- 기존 PR/이슈의 커밋 링크가 깨진다.
- 포크(Scincy/pini-engine)와 이미 클론한 사본에는 옛 이력이 남는다.
- GitHub 캐시에도 남을 수 있어, 확실히 지우려면 GitHub 지원에 요청해야 한다.

그래서 스크립트는 push 를 대신 하지 않고 안내만 출력한다.
`git-filter-repo` 가 지운 origin 은 다시 붙여 뒀다.

## 14.5 Play 앱 서명을 쓰고 있었다면

기존 앱이 Play 앱 서명(App Signing by Google Play)에 등록돼 있다면, 구글에 **업로드 키
교체**를 요청할 수 있다. 그 경우에는 신규 등록 없이 새 키로 업데이트를 계속할 수 있으니
새 앱을 올리기 전에 Play Console 을 먼저 확인할 것.

---

# 15. App Store 업로드 검증 실패 대응

아카이브·서명까지는 통과했는데 App Store Connect 업로드에서 5건이 걸렸다.
원인은 사실상 **두 가지**다.

## 15.1 앱 아이콘 — 에셋 카탈로그가 없었다

```
Missing required icon file. The bundle does not contain an app icon for
iPhone / iPod Touch of exactly '120x120' pixels ...   (iPad 152x152, iPad Pro 167x167 도 동일)
Missing Info.plist value. A value for the Info.plist key 'CFBundleIconName' is missing ...
```

헷갈리기 쉬운 점: **`Icon-120.png` 도 `Icon-152.png` 도 번들에 실제로 들어 있었다.**
그런데도 "없다"고 한다. **iOS 11 이후 SDK 로 빌드한 앱은 낱개 아이콘 파일을 인정하지
않고 에셋 카탈로그(`Assets.car`)에서만 아이콘을 찾기 때문**이다. 마지막 오류가 그 이유를
말해 준다. 즉 4건이 한 원인이다. (167x167 은 애초에 파일 자체가 없었다.)

조치:

- `ios/Images.xcassets/AppIcon.appiconset/` 추가. **크기 13종을 전부** 넣었다
  (20/29/40/58/60/76/80/87/120/152/167/180/1024). 원본은 `Engine/icon-1500.png`.
- **알파 채널을 제거**했다. App Store 는 알파가 있는 앱 아이콘을 거부한다.
- pbxproj: 파일 참조 + mobile 타겟 Resources 빌드 페이즈 + `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`

> **단일 크기 아이콘으로는 안 된다.** Xcode 14 부터 1024 한 장만 넣으면 나머지를
> 자동 생성해 준다고 알려져 있어서 처음엔 그렇게 했는데, 컴파일된 `Assets.car` 를
> `xcrun assetutil --info` 로 까 보니 **1024 렌디션 하나뿐**이었다. 검증이 요구하는
> 120/152/167 이 실제로는 없다. 크기별 png 를 명시적으로 넣어야 한다.
- Info.plist: `CFBundleIconName = AppIcon` 추가, `CFBundleIconFile`/`CFBundleIconFiles`/
  `CFBundleIconFiles~ipad` 삭제 (배포 타겟이 15.0 이라 하위호환 불필요),
  의미 없어진 `UIPrerenderedIcon` 삭제

### 게임별 아이콘

에셋 카탈로그는 `src`/`res` 처럼 폴더 참조로 바깥을 가리킬 수 없다. Xcode 프로젝트에
박힌 경로에서만 컴파일된다. 그래서 `ICON` 이 주어지면 **빌드 직전에 저장소의 아이콘들을
바꿔치기하고 끝나면 되돌린다.** 되돌리기는 `trap ... EXIT` 이라 중간에 죽어도 원복된다.

생성은 `scripts/make-ios-appicon.py` 가 한다. **크기 목록을 `Contents.json` 에서 읽으므로**
목록이 두 군데로 갈라지지 않는다. 정사각형이 아닌 소스는 가운데를 잘라낸다(늘리면 일그러진다).

> 이 방식은 같은 저장소에서 익스포트를 **동시에 두 개 돌리면 서로 간섭한다.**
> 지금 워크플로에서는 문제가 없지만, CI 에서 병렬로 돌릴 거라면 워크트리를 분리해야 한다.

## 15.2 iPad 멀티태스킹 방향

```
Invalid bundle. The "UIInterfaceOrientationLandscapeRight,UIInterfaceOrientationLandscapeLeft"
orientations were provided ... but you need to include all of the "...Portrait,
...PortraitUpsideDown, ...LandscapeLeft, ...LandscapeRight" orientations to support
iPad multitasking.
```

타겟이 유니버설(`TARGETED_DEVICE_FAMILY = "1,2"`)인데 가로 2방향만 선언해서 걸렸다.

조치:

- `UISupportedInterfaceOrientations~ipad` 에 4방향을 모두 선언 (검증 통과용)
- `UIRequiresFullScreen = true` 로 멀티태스킹 자체를 끔
- **`RootViewController.supportedInterfaceOrientations` 를 `UIInterfaceOrientationMaskLandscape`
  로 제한** — 원래는 `MaskAllButUpsideDown` 이었다. iPhone 은 plist 가 가로만 선언해서 결과가
  같았지만, iPad 에 세로를 추가한 지금은 여기서 막지 않으면 **실제로 세로로 돌아가** 비주얼
  노벨 화면이 레터박스로 깨진다.

  덤으로 반환형을 `NSUInteger` → `UIInterfaceOrientationMask` 로 고쳤다. iOS 6 시절 시그니처였다.

> iPhone 전용(`TARGETED_DEVICE_FAMILY = 1`)으로 바꾸면 iPad 아이콘·멀티태스킹 요구가
> 한꺼번에 사라진다. 제품 범위를 줄이는 결정이라 하지 않았다. iPad 를 포기해도 된다면
> 그쪽이 더 간단하다.

## 15.3 빌드 후 검증 추가

아카이브는 성공했는데 업로드에서 거부당하는 게 이 부류의 특징이다. `export-ios.sh` 가
아카이브 직후에 확인하도록 했다:

- `src/_export_execute_.lua` — 리소스 주입 확인 (기존)
- **`Assets.car`** — 에셋 카탈로그가 컴파일됐는지
- **`CFBundleIconName`** — Info.plist 키가 살아 있는지
- **아이콘 렌디션 120/152/167** — `xcrun assetutil --info` 로 실제로 들어 있는지.
  위의 단일 크기 함정을 잡아내는 검사다. `Assets.car` 가 있다는 것만으로는 부족하다.

## 15.4 아직 확인 안 된 것

`UIRequiresFullScreen` 은 iOS 26 SDK 기준으로 iPad 리사이즈 정책이 바뀌면서 무시될 수
있다. 그래서 `~ipad` 4방향 선언을 **함께** 넣었다. 둘 중 어느 쪽이 유효하든 검증은
통과하는 조합이다. 실제 업로드 결과로 확인이 필요하다.
