PiniEngine
=============
피니엔진은 비주얼 노벨 게임 제작도구입니다.

[![IMAGE ALT TEXT](http://img.youtube.com/vi/5FD2cSPqFLE/0.jpg)](http://www.youtube.com/watch?v=5FD2cSPqFLE "피니엔진 프리뷰 트레일러")

LNX 스크립트를 이용하여 게임을 개발하며 개발 및 빌드를 도와주는 에디터가 동봉되어있습니다.

피니에디터를 이용하여 개발 스크립트를 작성하고 작성된 스크립트는 PLY를 통해 컴파일 되며 만들어진 실행파일은 cocos2d-x엔진을 통해 실행됩니다.


LNX
-------------
LNX는 피니엔진용 스크립트언어입니다. 한글로 스크립팅할 수 있다는 특징이있습니다.

LNX의 형태는 아래와 같습니다.
<pre><code>#파라미터 알려줌
:야근시작
[대화 이름="김똘똘"]
;으윽! 야근인건가요?

직원수 = $프로그래머 + $그래픽 + $사운드 + $기획자 + $QA + $운영자
@조건 직원수 == 0:
	[대화 이름="김똘똘"]
	;하지만 야근을 할 직원이 없군요...
	>>주메뉴시작

[독백]
;야근을 하게되면 시간을 추가로 얻을 수 있습니다 하지만 사원들은 애사심이 떨어지고 애사심이 너무 떨어지면..
;퇴사를 하기도 합니다. 보너스로 달랠 수 있기는 합니다만.
;
;&lt;연결 "야근10"&gt;10시간 야근&lt;/연결&gt;
;&lt;연결 "야근20"&gt;20시간 야근&lt;/연결&gt;
;&lt;연결 "야근40"&gt;40시간 야근&lt;/연결&gt;
;
;&lt;연결 "야근포기"&gt;그만두자&lt;/연결&gt;
;
</code></pre>

설치
-------------
실행 파일은 [여기](http://piniengine.com/)에서 다운 받으실 수 있습니다.


현대화 현황
-------------
원본은 2015년경에 만들어졌고 Windows + Python 2.7 + PySide(Qt4) + cocos2d-x 3.15.1
조합이었습니다. 현재 macOS(Apple Silicon 네이티브) · iOS · Android 64bit 로 이식되어 있습니다.

| 항목 | 상태 |
|---|---|
| 에디터 | Python 3 + PySide6. macOS / Windows |
| 엔진 (macOS) | arm64 네이티브. Rosetta 불필요 |
| 엔진 (iOS) | arm64 실기기 빌드 + 에디터 익스포트 |
| 엔진 (Android) | arm64-v8a. Gradle(AGP 8) + NDK 27 |
| 엔진 (Windows) | 기존 Visual Studio 프로젝트 유지 |

이식 과정에서 내린 판단과 각 수정의 배경은 **[HANDOVER.md](HANDOVER.md)** 에 정리되어 있습니다.
빌드가 깨졌거나 원인을 모를 동작을 만났다면 그쪽을 먼저 보세요.

### 알려진 제약

- **iOS 시뮬레이터는 지원하지 않습니다.** cocos2d-x 프리빌트에 arm64 시뮬레이터
  슬라이스가 없어서 Apple Silicon 에서는 실기기 빌드만 됩니다.
- **동영상 재생은 Windows 에서만 됩니다.** ffmpeg 프리빌트가 win32 용밖에 없습니다.
  다른 플랫폼에서는 관련 API 가 no-op 입니다.
- **안드로이드 인앱결제는 스텁입니다.** 예전 AIDL v3 방식이 폐기되어, Play Billing 7+
  재작성 전까지는 실패 콜백만 돌려줍니다.
- **iOS / Android 실기기 동작 검증은 아직 못 했습니다.** 빌드까지만 확인된 상태입니다.


빌드 - 에디터 (macOS)
-------------
#### 필요
1. Python 3.11 이상
2. Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/HanbitGaram/pini-engine
cd pini-engine

pip3 install PySide6 lupa openpyxl pillow appdirs ply

# 에디터가 쓰는 네이티브 모듈(atl.so) 빌드
scripts/build-editor-natives.sh

cd Editor/pini
python3 main.py
```

> `lupa` 는 반드시 Lua 5.1(LuaJIT) 바인딩을 써야 합니다. 에디터는 `lupa.lua51` 을
> 명시적으로 임포트합니다. 엔진이 LuaJIT 이므로 버전이 어긋나면 미리보기 결과가
> 실제 실행과 달라집니다.

빌드 - 에디터 (Windows)
-------------
기존 방식이 그대로 유효합니다. `Editor/pini` 에 win32 확장 모듈이 포함되어 있습니다.

```bash
pip install PySide6 lupa openpyxl pillow appdirs ply
cd Editor/pini
python main.py
```


빌드 - 엔진 (macOS)
-------------
```bash
# 1. 외부 의존성 빌드 (libpng, freetype, chipmunk, LuaJIT, glfw ...)
scripts/build-deps-apple.sh

# 2. 엔진 빌드
scripts/build-mac.sh

# 3. 에디터가 쓰는 위치에 설치 (Engine/OSX.app 교체)
scripts/install-mac-runtime.sh
```

빌드 - 엔진 (iOS)
-------------
```bash
PLATFORM=ios scripts/build-deps-apple.sh
scripts/build-ios.sh
```

빌드 검증용이라 서명하지 않습니다. 설치 가능한 앱을 만들려면 아래 익스포트를 쓰세요.

빌드 - 엔진 (Android)
-------------
#### 필요
1. Android SDK (Platform 35)
2. NDK 27.1.12297006
3. JDK 17

```bash
# 1. ABI 별 네이티브 의존성 (LuaJIT, chipmunk, openssl ...)
scripts/build-deps-android.sh

# 2. APK
cd Engine/VisNovel/frameworks/runtime-src/proj.android
echo "sdk.dir=/path/to/Android/sdk" > local.properties
./gradlew assembleDebug
```

릴리스 서명키는 저장소에 넣지 않습니다. 새로 발급하려면:

```bash
scripts/make-release-keystore.sh
cd Engine/VisNovel/frameworks/runtime-src/proj.android
./gradlew assembleRelease
```

빌드 - 엔진 (Windows)
-------------
1. `Engine/VisNovel/frameworks/runtime-src/proj.win32/pini_remote.sln` 을 엽니다.
2. Visual Studio 에서 빌드합니다.
3. `runtime-src/Classes/ffmpeg/lib/window/*.dll` 을 `proj.win32/Debug.win32/` 로 복사합니다.
4. 에디터에 적용하려면 `Debug.win32/` 의 dll·exe 를 `Engine/window64/` 로 복사합니다.


게임 익스포트
-------------
에디터의 **파일 > 익스포트** 에서 플랫폼을 고릅니다.

| 플랫폼 | 필요한 것 | 비고 |
|---|---|---|
| 윈도우 | Windows | NSIS 인스톨러 생성 포함 |
| 안드로이드 | Windows + ADT/JDK | 구 도구체인 기반 |
| **iOS** | macOS + Xcode | 아래 참조 |

### iOS 익스포트

`파일 > 익스포트 > iOS...` 에서 앱 이름·번들 ID·버전·Apple 팀 ID 를 넣고 실행하면
`.ipa` 가 만들어집니다. 내부적으로는 `scripts/export-ios.sh` 를 부르며, 이 스크립트는
에디터 없이 커맨드라인에서도 쓸 수 있습니다.

```bash
STAGE=/path/to/stage \
OUTDIR=/path/to/out \
APP_NAME="내 게임" \
BUNDLE_ID=com.example.mygame \
TEAM_ID=XXXXXXXXXX \
METHOD=development \
scripts/export-ios.sh
```

`STAGE` 는 번들에 넣을 `src/` 와 `res/` 를 담은 디렉터리입니다. 에디터가 프로젝트를
컴파일해서 자동으로 만들어 줍니다.

`TEAM_ID` 를 비우면 서명 없이 `.xcarchive` 까지만 만듭니다. 실기기 설치와 스토어 제출에는
Apple Developer Program 가입이 필요합니다.

> 익스포트는 저장소의 `Engine/VisNovel/src`·`res` 를 덮어쓰지 않습니다. Xcode 타겟에
> 추가된 "Pini export stage" 빌드 페이즈가 `PINI_EXPORT_STAGE` 가 지정됐을 때만
> 번들 안의 리소스를 갈아끼웁니다. 개발·미리보기 워크플로는 그대로 동작합니다.

피니엔진 배포 빌드
-------------
```bash
cd Editor
python3 dist_pini.py
```


보안
-------------
과거 저장소에 안드로이드 서명키(`piniremote.keystore`)와 평문 비밀번호, Fabric API
시크릿이 커밋되어 있었습니다. 해당 키는 손상된 것으로 보고 폐기했으며 이력에서도
제거했습니다. 자세한 경위와 남은 조치는 [HANDOVER.md](HANDOVER.md) 를 참고하세요.

서명키·비밀번호는 `.gitignore` 로 막혀 있습니다. 다시 커밋하지 마세요.


해야하는 작업
-------------
- 에디터 자동저장 시 멈춤 / 메모리 사용량 급증 현상
- 업데이트하여 변화된 내용 위키에 표시
- Play Billing 7+ 로 안드로이드 인앱결제 재작성
- 안드로이드 동영상 재생을 MediaPlayer/ExoPlayer 로 재구현
- iOS / Android 실기기 동작 검증
- 안드로이드 익스포트를 mac 도구체인으로 재작성 (현재 Windows 전용)
