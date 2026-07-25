#ifndef __APP_DELEGATE_H__
#define __APP_DELEGATE_H__

#include "cocos2d.h"
#include "AppDelegateEvent.h"

#include <list>
using namespace std;

/* OpenAL 은 이제 win32 에서만 쓴다.
   - 안드로이드: 프리빌트가 armeabi/armeabi-v7a 뿐이라 arm64-v8a 를 막아서 걷어냈다.
   - mac/iOS: 애초에 alc* 호출이 없었다 (안드로이드 분기 전용이었다).
   win32 는 기존 동작을 그대로 두기 위해 헤더/멤버를 유지한다. */
#if (CC_TARGET_PLATFORM == CC_PLATFORM_WIN32)
#include "AL/al.h"
#include "AL/alc.h"
#endif

/**
@brief    The cocos2d Application.

The reason for implement as private inheritance is to hide some interface call by Director.
*/
class  AppDelegate : private cocos2d::Application
{
private:
	std::list<AppDelegateEvent*> _eventNode;
    
#if (CC_TARGET_PLATFORM == CC_PLATFORM_WIN32)
	ALCdevice		*m_pDevice;
	ALCcontext		*m_pALCtx;
#endif

	bool			 m_bFullscreen;
public:
	AppDelegate(bool fullscreen = false);
    virtual ~AppDelegate();

    virtual void initGLContextAttrs();

	void registEventNode(AppDelegateEvent*);
	void unregistEventNode(AppDelegateEvent*);
    /**
    @brief    Implement Director and Scene init code here.
    @return true    Initialize success, app continue.
    @return false   Initialize failed, app terminate.
    */
    virtual bool applicationDidFinishLaunching();

    /**
    @brief  The function be called when the application enter background
    @param  the pointer of the application
    */
    virtual void applicationDidEnterBackground();

    /**
    @brief  The function be called when the application enter foreground
    @param  the pointer of the application
    */
    virtual void applicationWillEnterForeground();
};

#endif  // __APP_DELEGATE_H__

