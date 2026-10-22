package com.hermesagent.hermes_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.util.Locale

/**
 * The foreground service that keeps this process — and with it the gateway
 * WebSocket owned by the Flutter engine — alive while the app is in the
 * background.
 *
 * Android freezes cached apps and Doze cuts their network, so an activity-only
 * app silently stops receiving approvals and turn completions as soon as the
 * user switches away. A foreground service with an ongoing (non-dismissible)
 * low-importance notification is the platform's sanctioned way to say "this
 * connection is still doing work", and it keeps both the process and its
 * sockets scheduled.
 *
 * The service itself is deliberately inert: the Flutter isolate already owns
 * the socket, so all this needs to do is stay foregrounded and let it run.
 * [START_STICKY] brings it back after a low-memory kill; the settings switch
 * (and [MainActivity]'s keep_alive channel) is the only way to stop it.
 */
class HermesConnectionService : Service() {
    companion object {
        /** Channel of the ongoing notification; the id the settings UI mirrors. */
        const val CHANNEL_ID = "hermes_connection"

        /** One fixed id: a repeated start updates the same row instead of stacking. */
        const val NOTIFICATION_ID = 4301

        /** Log tag: every start, refusal and promotion lands here. */
        private const val TAG = "HermesKeepAlive"

        /**
         * Brings the service up in the foreground.
         *
         * Returns whether the platform accepted the start request. A refusal
         * (API 31+ forbids foreground starts from the background, and an OEM
         * may block the type) is logged and reported instead of thrown: the
         * app keeps working with an ordinary, killable process.
         */
        fun start(context: Context): Boolean {
            val intent = Intent(context, HermesConnectionService::class.java)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                Log.w(TAG, "keep-alive start refused", e)
                false
            }
        }

        /** Stops the service; harmless when it is not running. */
        fun stop(context: Context): Boolean = try {
            context.stopService(Intent(context, HermesConnectionService::class.java))
        } catch (e: Exception) {
            Log.w(TAG, "keep-alive stop failed", e)
            false
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return try {
            startAsForeground()
            START_STICKY
        } catch (e: Exception) {
            // A refused promotion (permission stripped on a modified build, an
            // OEM that dislikes the type) must not take the app down with it.
            Log.w(TAG, "foreground promotion failed", e)
            stopSelf()
            START_NOT_STICKY
        }
    }

    /**
     * Promotes the service with the type declared in the manifest.
     *
     * `remoteMessaging` (API 34+) is exactly this use case — a persistent
     * messaging connection — and is exempt from the data-sync time limit that
     * would otherwise stop the socket after six hours. Older platforms have no
     * such type, so 29–33 fall back to `dataSync` and below that the type is
     * not part of the API at all.
     */
    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        Log.i(TAG, "keep-alive foreground sdk=${Build.VERSION.SDK_INT}")
    }

    /**
     * The ongoing notification: low importance, silent, and not dismissible
     * (setOngoing) so the user's way out is the app's own switch rather than a
     * swipe that leaves a live socket with no visible owner.
     */
    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(t("Hermes 保持连接", "Hermes connection active"))
            .setContentText(t("后台接收审批与完成通知", "Receiving approvals and completions"))
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            t("保持连接", "Connection"),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = t(
                "后台接收审批与完成通知",
                "Keeps the gateway socket open in the background",
            )
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun t(zh: String, en: String): String =
        if (Locale.getDefault().language.startsWith("zh")) zh else en
}
