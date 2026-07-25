/****************************************************************************
 * Cocos2dxEngineDataManager — no-op 스텁
 *
 * 원본은 특정 OEM 의 "engine data" 서비스(org.cocos2dx.enginedata.IEngineDataManager 등)와
 * AIDL 로 붙어 CPU/GPU 성능 힌트를 주고받는 선택적 연동이었다.
 * **그 인터페이스 파일들은 이 저장소에 들어 있지 않아서** 그대로는 컴파일되지 않는다
 * (원래 ant 빌드에서는 cocos 자바를 라이브러리 프로젝트로 따로 빌드해 우회했던 것으로 보인다).
 *
 * Cocos2dxActivity 가 init/resume/pause/destroy 네 개를 부르므로, 그 시그니처만 유지한
 * 아무 일도 하지 않는 구현으로 대체한다. 성능 힌트를 못 받을 뿐 게임 동작에는 영향이 없다.
 * 원본은 Cocos2dxEngineDataManager.java.orig 로 남겨 두었다.
 ****************************************************************************/
package org.cocos2dx.lib;

import android.content.Context;
import android.opengl.GLSurfaceView;

public class Cocos2dxEngineDataManager {

    public static void disable() { }

    public static boolean isInited() { return false; }

    public static boolean init(Context context, final GLSurfaceView glSurfaceView) { return false; }

    public static void destroy() { }

    public static void pause() { }

    public static void resume() { }

    public static String getVendorInfo() { return ""; }

    public static void notifyGameStatus(int gameStatus, int cpuLevel, int gpuLevel) { }

    public static void notifyContinuousFrameLost(int cycle, int continuousFrameLostThreshold, int times) { }

    public static void notifyLowFps(int cycle, float lowFpsThreshold, int lostFrameCount) { }

    public static void notifyFpsChanged(float oldFps, float newFps) { }
}
