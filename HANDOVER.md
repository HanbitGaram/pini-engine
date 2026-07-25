# PiniEngine 현대화 인수인계 문서

> 작성일: 2026-07-25. 이 문서는 Claude(Fable) 세션에서 수행한 사전 조사 결과와 실행 계획을
> 다른 세션(Opus 등)이 이어받아 작업할 수 있도록 정리한 것이다.
> 목표: **(1) macOS에서 에디터+엔진 구동, (2) iOS 배포, (3) Android 배포.**

## 0. 현재 상태 (이미 완료된 것)

- 작업 브랜치: `modernize/mac-ios-android` (master에서 분기, 아직 커밋 없음)
- 로컬 Python 3.13.7 (`/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`)에
  PySide6 6.11.1, lupa 2.8, Pillow, openpyxl, appdirs, ply 설치 완료 (pip 네트워크 사용 가능)
- 코드 수정은 아직 하나도 하지 않았다.

## 1. 환경 사실 (검증됨)

| 항목 | 값 |
|---|---|
| 머신 | Apple Silicon (arm64), macOS 15.7.5, **Rosetta 2 설치됨** |
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
  → **1차 전략 확정: `ARCHS=x86_64`로 빌드해 Rosetta로 구동.** (Rosetta 설치 확인됨)
  arm64 네이티브는 13개 라이브러리 재빌드 필요. 특히 **LuaJIT**(x86_64-thin, 2.0계열은
  arm64-macOS 미지원)가 최난관 — arm64로 가려면 LuaJIT 2.1 빌드 또는 일반 Lua 5.1 전환 필요.
  mac용 일반 lua 프리빌트도 없음(`lua/lua/prebuilt`는 ios만 존재).
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

### Phase 1 — macOS 엔진 빌드 (가장 먼저; 다른 모든 것의 기반)
1. mac 타겟 Sources에 누락된 게임 C++ 추가 (§4.3-1 목록 — iOS 타겟 소스 목록을 기준으로,
   단 `VideoPlayer.cpp`가 아니라 스텁인 `VideoPlayer_iOS.cpp`를 사용)
2. mac 타겟 헤더 경로에 `$(SRCROOT)/../Classes/openal/include` 추가 (§4.3-2)
3. `.dylib` 링크 참조를 `.tbd`/`-l` 플래그로 교체 (§4.3-6)
4. `xcodebuild -project ... -target pini_remote-desktop -arch x86_64 ONLY_ACTIVE_ARCH=NO build`
   → 컴파일 에러 반복 수정. C++ 표준은 `gnu++14` 강제 + `-Wno-*` 완화.
   cocos2d-x 쪽 수정은 최소한으로. 서브프로젝트 3개(cocos2d_libs, lua_bindings, libsimulator)도
   같은 방식으로 설정 오버라이드 (`xcodebuild` 커맨드라인 `GCC_...`/`CLANG_...` 오버라이드가
   서브프로젝트에도 전파되므로 프로젝트 파일 수정을 최소화할 수 있음).
5. LuaJIT 유지 → `-image_base/-pagezero_size` 플래그 보존 (§4.3-5)
6. 산출물 .app을 `Engine/OSX.app`로 교체 배치(기존 것은 백업) 후 실행 확인
7. 성공 기준: Rosetta로 창이 뜨고 45674 포트 리슨, 에디터에서 씬 전송 시 렌더링

### Phase 2 — 에디터 py3/PySide6 포팅 (§3.5 순서대로)
- 성공 기준: 에디터 구동 → 샘플 프로젝트(`Editor/sample_proj/`) 열기 → LNX 컴파일 →
  Phase 1 엔진으로 "실행" 동작.

### Phase 3 — iOS
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
