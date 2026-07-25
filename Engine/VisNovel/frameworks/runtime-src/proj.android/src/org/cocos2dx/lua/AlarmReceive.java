/****************************************************************************
 * 로컬 알림(예약 푸시) 수신기.
 *
 * 원본은 API 11 이전에 제거된 API 로 작성되어 있어 현행 SDK 에서는 컴파일조차 안 됐다:
 *   - new Notification(icon, ticker, when)   : API 11 deprecated -> 제거됨
 *   - notify.setLatestEventInfo(...)         : API 23 에서 제거됨
 * 또 API 26(오레오)부터는 채널 없이 알림을 띄울 수 없다.
 * NotificationCompat + NotificationChannel 로 다시 썼다.
 ****************************************************************************/
package org.cocos2dx.lua;

import androidx.core.app.NotificationCompat;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;

import com.nooslab.pini_remote_landscape.R;

public class AlarmReceive extends BroadcastReceiver {

    private static final String CHANNEL_ID = "pini_local_push";

    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            NotificationManager notifier =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (notifier == null) return;

            // API 26+ 는 채널이 없으면 알림이 아예 표시되지 않는다.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "알림", NotificationManager.IMPORTANCE_DEFAULT);
                notifier.createNotificationChannel(channel);
            }

            Bundle extras = intent.getExtras();
            String title = extras != null ? extras.getString("title") : null;
            String text  = extras != null ? extras.getString("text")  : null;
            String sendId = extras != null ? extras.getString("name") : null;
            int vibrate  = extras != null ? extras.getInt("vibrate", 0) : 0;

            Intent open = new Intent(context, AppActivity.class)
                    .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra("sendId", sendId);

            // API 31 부터 PendingIntent 는 mutability 를 명시해야 한다.
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent contentIntent = PendingIntent.getActivity(context, 0, open, flags);

            NotificationCompat.Builder builder =
                new NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.drawable.icon)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setTicker(title)
                    .setWhen(System.currentTimeMillis())
                    .setAutoCancel(true)
                    .setContentIntent(contentIntent);

            notifier.notify(1, builder.build());

            if (vibrate != 0) {
                Vibrator vibe = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
                if (vibe != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibe.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE));
                    } else {
                        vibe.vibrate(100);
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
