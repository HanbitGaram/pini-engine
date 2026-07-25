/****************************************************************************
 * PiniEngine Android 액티비티
 *
 * [1차 릴리즈 범위 축소 — HANDOVER.md §6 Phase 4-6]
 * 예전 버전은 여기서 광고 SDK 4종(Cauly/Adop/UPlusAD/Vungle), Fabric/Crashlytics,
 * OBB 확장파일 다운로더(play_apk_expansion), LVL licensing, AIDL v3 인앱결제까지
 * 전부 다뤘다. 전부 서비스가 종료됐거나 현행 SDK 에서 동작하지 않아 걷어냈다.
 *
 * 다만 **Lua 가 호출하는 static 메서드의 이름과 시그니처는 그대로 유지**한다.
 * 게임 Lua(PiniLib.lua)가 luaj.callStaticMethod 로 이 클래스를 직접 부르기 때문이다.
 * 특히 결제/OBB 는 Lua 쪽에서 VM 을 멈추고(vm:stop()) 콜백을 기다리므로,
 * 스텁이라도 **반드시 콜백을 돌려줘야** 게임이 멈추지 않는다.
 *
 * 되살릴 때 참고: 원본은 AppActivity.java.orig-ant 로 남겨 두었다.
 ****************************************************************************/
package org.cocos2dx.lua;

import java.util.Calendar;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxLuaJavaBridge;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Vibrator;
import android.os.VibrationEffect;
import android.view.View;
import android.view.WindowManager;
import android.widget.Toast;

public class AppActivity extends Cocos2dxActivity {
    static AppActivity _this;

    /** LVL licensing 용이었다. 지금은 보관만 한다. */
    public String PUBLIC_KEY = "";

    static String hostIPAdress = "0.0.0.0";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        AppActivity._this = this;

        if (nativeIsLandScape()) {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        } else {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT);
        }

        if (nativeIsDebug()) {
            // 에디터와 TCP 로 붙는 리모트 모드에서는 화면이 꺼지면 곤란하다.
            getWindow().setFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                                 WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            hostIPAdress = getHostIpAddress();
        }
    }

    // ---------------------------------------------------------------- 기능 ----

    public void _Toast(final String str, final int time) {
        runOnUiThread(new Runnable() {
            @Override public void run() {
                try { Toast.makeText(AppActivity.this, str, time).show(); }
                catch (Exception e) { e.printStackTrace(); }
            }
        });
    }

    public void _Vibrator(final long ms) {
        runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    Vibrator vibe = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                    if (vibe == null) return;
                    // API 26 부터 vibrate(long) 은 deprecated 다.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibe.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE));
                    } else {
                        vibe.vibrate(ms);
                    }
                } catch (Exception e) { e.printStackTrace(); }
            }
        });
    }

    public void _localPush(final String title, final String text, final int vibrate,
                           final int day, final int hour, final int min, final int sec) {
        runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    Calendar cal = Calendar.getInstance();
                    cal.add(Calendar.DATE, day);
                    cal.add(Calendar.HOUR_OF_DAY, hour);
                    cal.add(Calendar.MINUTE, min);
                    cal.add(Calendar.SECOND, sec);

                    Intent intent = new Intent(AppActivity.this, AlarmReceive.class);
                    intent.putExtra("title", title);
                    intent.putExtra("text", text);
                    intent.putExtra("vibrate", vibrate);

                    // API 31 부터 PendingIntent 는 mutability 를 명시해야 한다.
                    int flags = PendingIntent.FLAG_UPDATE_CURRENT;
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        flags |= PendingIntent.FLAG_IMMUTABLE;
                    }
                    PendingIntent sender =
                        PendingIntent.getBroadcast(AppActivity.this, 192837, intent, flags);

                    AlarmManager am = (AlarmManager) getSystemService(ALARM_SERVICE);
                    if (am != null) am.set(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), sender);
                } catch (Exception e) { e.printStackTrace(); }
            }
        });
    }

    public void CallLua(final String funcName, final String arg) {
        runOnGLThread(new Runnable() {
            @Override public void run() {
                try { Cocos2dxLuaJavaBridge.callLuaGlobalFunctionWithString(funcName, arg); }
                catch (Exception e) { e.printStackTrace(); }
            }
        });
    }

    public String getHostIpAddress() {
        try {
            WifiManager wifiMgr = (WifiManager)
                getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wifiMgr == null) return "0.0.0.0";
            WifiInfo wifiInfo = wifiMgr.getConnectionInfo();
            int ip = wifiInfo.getIpAddress();
            return ((ip & 0xFF) + "." + ((ip >>>= 8) & 0xFF) + "."
                                 + ((ip >>>= 8) & 0xFF) + "." + ((ip >>>= 8) & 0xFF));
        } catch (Exception e) {
            return "0.0.0.0";
        }
    }

    // ------------------------------------------------- Lua 브릿지용 static ----
    // 이름/시그니처는 PiniLib.lua 가 그대로 부르므로 바꾸면 안 된다.

    /** 결제 결과를 Lua 로 돌려준다. Lua 는 "result" 값만 본다(PiniLib.PINI_IAP_CALLBACK). */
    private static void iapFail() {
        if (_this != null) _this.CallLua("PINI_IAP_CALLBACK", "{\"result\":false}");
    }

    public static void IAB_Settings(String hash) {
        // AIDL v3 결제는 제거됐다. Play Billing 7+ 로 재작성하는 것이 후속 과제다.
    }
    public static void IAB_Buy(String id_item)     { iapFail(); }
    public static void IAB_Consume(String id)      { iapFail(); }
    public static void IAB_Check(String id_item)   { iapFail(); }

    public static void Android_Toast(String str, float time) {
        if (_this != null) _this._Toast(str, (int) time);
    }

    // 광고 SDK 4종은 모두 서비스가 종료되어 제거했다. 호출은 조용히 무시한다.
    public static void ADS_Fullscreen() { }
    public static void ADS_Banner()     { }
    public static void VungleInit(String appId) { }
    public static void VunglePlay()     { }

    public static void Device_LocalPush(String title, String text, float vibrate,
                                        float day, float hour, float min, float sec) {
        if (_this != null) {
            _this._localPush(title, text, (int) vibrate, (int) day, (int) hour, (int) min, (int) sec);
        }
    }

    public static void Device_Vibrator(float ms) {
        if (_this != null) _this._Vibrator((long) ms);
    }

    /* OBB 확장파일은 쓰지 않는다 (리소스를 APK/AAB 에 넣는다).
       "이미 있다" 고 답해서 Lua 가 다운로드 단계를 건너뛰게 한다. */
    public static boolean ExtensionFile_IsFileExists(String type, String versionCode, String size) {
        return true;
    }
    public static void ExtensionFile_Download() {
        // Lua 는 여기서 VM 을 멈추고 결과를 기다린다. 즉시 성공으로 답해 줘야 멈추지 않는다.
        if (_this != null) _this.CallLua("PINI_OBB_DOWNLOAD_RESULT", "1");
    }
    public static void Extension_SetPublicKey(String pkey) {
        if (_this != null) _this.PUBLIC_KEY = pkey;
    }

    public static String AppPackageName() {
        return _this != null ? _this.getPackageName() : "";
    }
    /** OBB 를 쓰지 않으므로 앱 전용 외부 저장소 경로를 돌려준다. */
    public static String OBBDirPath() {
        if (_this == null) return "";
        java.io.File dir = _this.getExternalFilesDir(null);
        return dir != null ? dir.getAbsolutePath() : _this.getFilesDir().getAbsolutePath();
    }

    public static void HideSoftKey() {
        if (_this == null) return;
        View decorView = _this.getWindow().getDecorView();
        decorView.setSystemUiVisibility(View.SYSTEM_UI_FLAG_HIDE_NAVIGATION);
    }

    public static String getLocalIpAddress() { return hostIPAdress; }

    private static native boolean nativeIsLandScape();
    private static native boolean nativeIsDebug();

    static {
        /* 예전에는 여기서 ffmpeg(avutil/avcodec/avformat/swresample/swscale)와 openal 을
           System.loadLibrary 로 올렸다. 그 프리빌트들은 32bit armeabi 밖에 없어 arm64-v8a
           를 막았고, 비디오 플레이어를 스텁으로 돌리면서 필요가 없어졌다.
           cocos2dlua 본체는 Cocos2dxActivity 가 매니페스트의 android.app.lib_name 을 보고 올린다. */
    }
}
