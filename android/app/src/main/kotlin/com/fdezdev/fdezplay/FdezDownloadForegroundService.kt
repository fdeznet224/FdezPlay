package com.fdezdev.fdezplay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class FdezDownloadForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == ACTION_STOP) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        val activeDownloads = intent?.getIntExtra(EXTRA_ACTIVE_DOWNLOADS, 1) ?: 1
        createNotificationChannel()
        val notification = buildNotification(activeDownloads)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun buildNotification(activeDownloads: Int): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingOpenIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val title = if (activeDownloads > 1) {
            "Descargando $activeDownloads contenidos"
        } else {
            "Descargando contenido"
        }

        val text = "FdezPlay seguirá descargando mientras usas otra app."

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingOpenIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Descargas FdezPlay",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mantiene activas las descargas de películas y series."
            setShowBadge(false)
        }

        manager.createNotificationChannel(channel)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    companion object {
        const val ACTION_START = "com.fdezdev.fdezplay.DOWNLOAD_FOREGROUND_START"
        const val ACTION_STOP = "com.fdezdev.fdezplay.DOWNLOAD_FOREGROUND_STOP"
        const val EXTRA_ACTIVE_DOWNLOADS = "active_downloads"

        private const val CHANNEL_ID = "fdezplay_downloads"
        private const val NOTIFICATION_ID = 22401
    }
}
