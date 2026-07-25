#include "AppDelegate.h"
#include "scripting/lua-bindings/manual/CCLuaEngine.h"
#include "cocos2d.h"
#include "lua_module_register.h"

#include "md5/md5.h"

#if (CC_TARGET_PLATFORM != CC_PLATFORM_LINUX)
#include "ide-support/CodeIDESupport.h"
#endif

#if (COCOS2D_DEBUG > 0) && (CC_CODE_IDE_DEBUG_SUPPORT > 0)
#include "runtime/Runtime.h"
#include "ide-support/RuntimeLuaImpl.h"
#endif
#include "ATL.h"

#include "lua_utils.h"

/* ffmpeg 프리빌트는 android(armeabi) 와 windows(x86) 만 있고 mac/iOS 용이 없다.
   iOS 와 마찬가지로 mac 도 전 메서드가 no-op 인 VideoPlayer_iOS 스텁을 쓴다.
   (비디오 재생 기능 비활성 — HANDOVER.md §4.5) */
#if (CC_TARGET_PLATFORM == CC_PLATFORM_IOS || CC_TARGET_PLATFORM == CC_PLATFORM_MAC)
#include "VideoPlayer_iOS.h"
#else
#include "VideoPlayer.h"
#endif

#include "TextInput.h"
#include "audio/include/AudioEngine.h"

#include "AsyncLoaderManager.h"

USING_NS_CC;
using namespace std;
using namespace cocos2d;

#ifdef __cplusplus
extern "C" {
#endif
    static luaL_Reg luax_exts[] = {
        { "md5.core", luaopen_md5_core },
        { "plua.utils", luaopen_luautils_core },
        { NULL, NULL }
    };

    void LuaPackageExtension(lua_State *L)
    {
        // load extensions
        luaL_Reg* lib = luax_exts;
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "preload");
        for (; lib->func; lib++)
        {
            lua_pushcfunction(L, lib->func);
            lua_setfield(L, -2, lib->name);
        }
        lua_pop(L, 2);

        tolua_open(L);
        tolua_module(L, "npini", 0);
        tolua_beginmodule(L, "npini");

        luaopen_VideoPlayer_core(L);
        luaopen_TextInput_core(L);

        tolua_endmodule(L);

    }
#ifdef __cplusplus
}
#endif

AppDelegate::AppDelegate(bool fullscreen)
{
	m_bFullscreen = fullscreen;
#if (CC_TARGET_PLATFORM == CC_PLATFORM_ANDROID )
	m_pDevice = alcOpenDevice(NULL);
	m_pALCtx = alcCreateContext(m_pDevice, NULL);
	alcMakeContextCurrent(m_pALCtx);
	if (!m_pALCtx)
	{
		//CCLOG("Oops2\n");
	}
	//CCLOG(">>> %d", m_pALCtx);
#else
#endif
	// experimental::AudioEngine::lazyInit();	
	ATL::getInstance();
}

AppDelegate::~AppDelegate()
{
    //SimpleAudioEngine::end();

#if (COCOS2D_DEBUG > 0) && (CC_CODE_IDE_DEBUG_SUPPORT > 0)
    // NOTE:Please don't remove this call if you want to debug with Cocos Code IDE
    RuntimeEngine::getInstance()->end();
#endif
	
#if (CC_TARGET_PLATFORM == CC_PLATFORM_ANDROID )
	alcDestroyContext(m_pALCtx);
	alcMakeContextCurrent(NULL);
	alcCloseDevice(m_pDevice);
#else
#endif
	experimental::AudioEngine::stopAll();
	experimental::AudioEngine::end();
	ATL::destroy();

	string path = FileUtils::getInstance()->getWritablePath();
	if (FileUtils::getInstance()->isDirectoryExist(path + "tmp/"))
		FileUtils::getInstance()->removeDirectory(path + "tmp/");
	AsyncLoaderManager::purge();
}

//if you want a different context,just modify the value of glContextAttrs
//it will takes effect on all platforms
void AppDelegate::initGLContextAttrs()
{
    //set OpenGL context attributions,now can only set six attributions:
    //red,green,blue,alpha,depth,stencil
    GLContextAttrs glContextAttrs = {8, 8, 8, 8, 24, 8};

    GLView::setGLContextAttrs(glContextAttrs);
}

// If you want to use packages manager to install more packages,
// don't modify or remove this function
static int register_all_packages()
{
    return 0; //flag for packages manager
}

bool AppDelegate::applicationDidFinishLaunching()
{
#if (CC_TARGET_PLATFORM == CC_PLATFORM_MAC)
	/* cocos 의 mac 기본 쓰기 경로는 ~/Documents/ 인데(CCFileUtils-apple.mm), 두 가지 문제가 있다.
	   1) macOS 는 ~/Documents 를 개인정보 보호(TCC)로 보호한다. 권한이 없으면 파일 쓰기가
	      조용히 실패해서, 에디터가 보낸 리소스가 하나도 저장되지 않고 테스트 실행이 먹통이 된다.
	   2) 에디터는 appdirs 의 user_data_dir("pini_remote") 즉
	      ~/Library/Application Support/pini_remote 를 쓴다. 서로 다른 곳을 보고 있었다.
	   Application Support 로 맞추면 둘 다 해결된다 (앱 데이터를 두기에도 여기가 맞다).
	   Lua 가 getWritablePath() 를 쓰기 전에, 아래 아무 초기화보다도 먼저 지정해야 한다. */
	{
		const char* home = getenv("HOME");
		if (home != nullptr)
		{
			std::string appSupport = std::string(home) + "/Library/Application Support/pini_remote/";
			FileUtils::getInstance()->createDirectory(appSupport);
			FileUtils::getInstance()->setWritablePath(appSupport);
		}
	}
#endif

    // set default FPS
    Director::getInstance()->setAnimationInterval(1.0 / 60.0f);

    // register lua module
    auto engine = LuaEngine::getInstance();
    ScriptEngineManager::getInstance()->setScriptEngine(engine);
    lua_State* L = engine->getLuaStack()->getLuaState();
    lua_module_register(L);
	LuaPackageExtension(L);

    register_all_packages();

    LuaStack* stack = engine->getLuaStack();
    stack->setXXTEAKeyAndSign("2dxLua", strlen("2dxLua"), "XXTEA", strlen("XXTEA"));

    //register custom function
    //LuaStack* stack = engine->getLuaStack();
    //register_custom_function(stack->getLuaState());

	if (m_bFullscreen){
		engine->executeString("_FULLSCREEN = true");
	} else{
		engine->executeString("_FULLSCREEN = false");
	}

	CCFileUtils::getInstance()->addSearchPath("src", true);
	CCFileUtils::getInstance()->addSearchPath("res", true);

//#if (COCOS2D_DEBUG > 0) && (CC_CODE_IDE_DEBUG_SUPPORT > 0)
//    // NOTE:Please don't remove this call if you want to debug with Cocos Code IDE
//    auto runtimeEngine = RuntimeEngine::getInstance();
//    runtimeEngine->addRuntime(RuntimeLuaImpl::create(), kRuntimeEngineLua);
//    runtimeEngine->start();
//#else
    if (engine->executeScriptFile("src/main.lua"))
    {
        return false;
    }
//#endif

    return true;
}

// This function will be called when the app is inactive. When comes a phone call,it's be invoked too
void AppDelegate::applicationDidEnterBackground()
{
    Director::getInstance()->stopAnimation();

	// experimental::AudioEngine::pauseAll();

	list<AppDelegateEvent*>::iterator b = _eventNode.begin();
	list<AppDelegateEvent*>::iterator e = _eventNode.end();
	for (; b != e; b++){
		(*b)->onBackground();
	}
}

// this function will be called when the app is active again
void AppDelegate::applicationWillEnterForeground()
{
    Director::getInstance()->startAnimation();

	// experimental::AudioEngine::resumeAll();

	list<AppDelegateEvent*>::iterator b = _eventNode.begin();
	list<AppDelegateEvent*>::iterator e = _eventNode.end();
	for (; b != e; b++){
		(*b)->onForeground();
	}
}

void AppDelegate::registEventNode(AppDelegateEvent* p){
	list<AppDelegateEvent*>::iterator b = _eventNode.begin();
	list<AppDelegateEvent*>::iterator e = _eventNode.end();
	for (; b != e; b++){
		if ((*b) == p){
			return;
		}
	}
	_eventNode.push_back(p);
}

void AppDelegate::unregistEventNode(AppDelegateEvent* p){
	list<AppDelegateEvent*>::iterator b = _eventNode.begin();
	list<AppDelegateEvent*>::iterator e = _eventNode.end();
	for (; b != e; b++){
		if ((*b) == p){
			_eventNode.erase(b);
			return;
		}
	}
}
