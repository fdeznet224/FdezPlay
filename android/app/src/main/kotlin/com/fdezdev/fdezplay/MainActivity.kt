package com.fdezdev.fdezplay

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val downloadChannel = "com.fdezdev.fdezplay/background_download"
    private val pipChannel = "com.fdezdev.fdezplay/picture_in_picture"

    private var pipPlayerActive = false
    private var pipWidth = 16
    private var pipHeight = 9

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val active = call.argument<Int>("active") ?: 1
                    startDownloadForegroundService(active)
                    result.success(true)
                }

                "update" -> {
                    val active = call.argument<Int>("active") ?: 1
                    startDownloadForegroundService(active)
                    result.success(true)
                }

                "stop" -> {
                    stopService(Intent(this, FdezDownloadForegroundService::class.java))
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pipChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isPictureInPictureSupported())

                "setActive" -> {
                    pipPlayerActive = call.argument<Boolean>("active") ?: false
                    pipWidth = sanitizeRatioValue(call.argument<Int>("width") ?: 16)
                    pipHeight = sanitizeRatioValue(call.argument<Int>("height") ?: 9)
                    result.success(true)
                }

                "enter" -> {
                    val width = sanitizeRatioValue(call.argument<Int>("width") ?: pipWidth)
                    val height = sanitizeRatioValue(call.argument<Int>("height") ?: pipHeight)
                    result.success(enterPictureInPicture(width, height))
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        if (pipPlayerActive) {
            enterPictureInPicture(pipWidth, pipHeight)
        }
        super.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    private fun isPictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun enterPictureInPicture(width: Int, height: Int): Boolean {
        if (!isPictureInPictureSupported() || isFinishing || isDestroyed) {
            return false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
            return true
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(sanitizeRatioValue(width), sanitizeRatioValue(height)))

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(true)
                }

                enterPictureInPictureMode(builder.build())
            } else {
                false
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun sanitizeRatioValue(value: Int): Int {
        return value.coerceIn(1, 100)
    }

    private fun startDownloadForegroundService(active: Int) {
        val intent = Intent(this, FdezDownloadForegroundService::class.java).apply {
            action = FdezDownloadForegroundService.ACTION_START
            putExtra(FdezDownloadForegroundService.EXTRA_ACTIVE_DOWNLOADS, active)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
