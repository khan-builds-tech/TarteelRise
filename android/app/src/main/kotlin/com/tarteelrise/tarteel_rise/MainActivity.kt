package com.tarteelrise.tarteel_rise

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Android 14+ (API 34) demotes USE_FULL_SCREEN_INTENT to a special
// permission: declaring it in the manifest is no longer sufficient to
// auto-launch the ringing activity over the lock screen — the OS can grant
// it automatically for well-behaved apps, or silently downgrade a fired
// alarm to an ordinary heads-up notification. There is no `permission_handler`
// support for this (it isn't a normal runtime permission dialog), so this
// channel exposes the two calls Android does provide: checking the current
// grant, and deep-linking to the one Settings screen that lets the user
// flip it on.
private const val FULL_SCREEN_INTENT_CHANNEL = "com.tarteelrise.tarteel_rise/full_screen_intent"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FULL_SCREEN_INTENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canUseFullScreenIntent(): Boolean {
        // The special-permission gate only exists from API 34 onward; below
        // that, `USE_FULL_SCREEN_INTENT` in the manifest is unconditionally
        // honored.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        return notificationManager?.canUseFullScreenIntent() ?: true
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return
        }
        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }
}
