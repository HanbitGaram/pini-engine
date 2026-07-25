#ifndef _PINI_C_UTILS_
#define _PINI_C_UTILS_

#ifndef GPP_FOR_PYTHON
#include "cocos2d.h"
#endif

#include <stdlib.h>

/* GPP_FOR_PYTHON (에디터가 ctypes 로 읽는 atl.so 빌드) 에서는 cocos2d.h 를 포함하지
   않으므로 CC_TARGET_PLATFORM 과 CC_PLATFORM_WIN32 가 둘 다 정의되지 않는다.
   C 전처리기는 정의되지 않은 식별자를 0 으로 보므로 아래 비교가 0 == 0 => 참이 되어
   윈도우가 아닌 곳에서도 <windows.h> 를 포함하려다 실패했다. 그래서 이 빌드에서는
   컴파일러가 주는 _WIN32 로 판정한다. cocos 빌드 쪽 동작은 이전과 동일하다. */
#if defined(GPP_FOR_PYTHON)
#  if defined(_WIN32)
#    define PINI_UTILS_WIN32 1
#  else
#    define PINI_UTILS_WIN32 0
#  endif
#else
#  define PINI_UTILS_WIN32 (CC_TARGET_PLATFORM == CC_PLATFORM_WIN32)
#endif

#if PINI_UTILS_WIN32
#include <windows.h>
#else
#include <unistd.h>
extern void Sleep(float t);
#endif

#endif
