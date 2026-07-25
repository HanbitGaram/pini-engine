#ifndef __APP_DELEGATE_H__
#define __APP_DELEGATE_H__

#include "cocos2d.h"
#include "AppDelegateEvent.h"

#include <list>
using namespace std;

#if (CC_TARGET_PLATFORM == CC_PLATFORM_MAC)
/* macOS 에는 Classes/openal (안드로이드용 OpenAL Soft 헤더) 를 쓰지 않고 시스템
   OpenAL.framework 를 쓴다. 실제 alc* 호출은 안드로이드 분기에만 있고, mac 에서는
   ALCdevice/ALCcontext 타입 선언만 필요하다. */
#include <OpenAL/al.h>
#include <OpenAL/alc.h>
#elif (CC_TARGET_PLATFORM != CC_PLATFORM_IOS)
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
    
#if (CC_TARGET_PLATFORM != CC_PLATFORM_IOS)
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

