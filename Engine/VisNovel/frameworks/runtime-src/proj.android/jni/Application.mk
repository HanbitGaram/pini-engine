# NDK r18 부터 gnustl 이 제거되었다 (원래 값: gnustl_static). c++_static 으로 전환.
APP_STL := c++_static

# 예전에는 APP_ABI 를 지정하지 않아 cocos 콘솔 기본값인 armeabi(32bit) 로만 빌드됐다.
# 플레이스토어는 2019년부터 64bit 를 필수로 요구한다.
APP_ABI := arm64-v8a armeabi-v7a

# minSdk 24 (§6 Phase 4-7). NDK 27 이 지원하는 하한은 21 이다.
APP_PLATFORM := android-24

APP_CPPFLAGS := -frtti -DCC_ENABLE_CHIPMUNK_INTEGRATION=1 -DCC_ENABLE_BULLET_INTEGRATION=1 -std=c++14 -fsigned-char
APP_LDFLAGS := -latomic

# cocos 가 vendored 한 pvmp3dec(MP3 디코더)는 자체 Android.mk 에서 -Werror 를 켠다.
# 최신 clang 이 새로 추가한 경고 때문에 고정소수점 상수 계산이 에러로 승격되는데,
# 값 자체는 의도된 것이라 경고만 끈다.
APP_CFLAGS += -Wno-implicit-const-int-float-conversion

ifeq ($(NDK_DEBUG),1)
  APP_CPPFLAGS += -DCOCOS2D_DEBUG=1
  APP_OPTIM := debug
else
  APP_CPPFLAGS += -DNDEBUG
  APP_OPTIM := release
endif
