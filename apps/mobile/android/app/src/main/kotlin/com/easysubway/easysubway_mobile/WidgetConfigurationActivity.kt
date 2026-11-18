package com.easysubway.easysubway_mobile

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class WidgetConfigurationActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        applyScreenOrientationPolicy(resources.configuration)
        super.onCreate(savedInstanceState)
        if (!hasValidOwnedAppWidget(intent)) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
    }

    override fun onNewIntent(intent: Intent) {
        if (!hasValidOwnedAppWidget(intent)) {
            return
        }
        super.onNewIntent(intent)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyScreenOrientationPolicy(newConfig)
    }

    private fun applyScreenOrientationPolicy(configuration: Configuration) {
        requestedOrientation = if (configuration.smallestScreenWidthDp < 600) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    private fun hasValidOwnedAppWidget(targetIntent: Intent?): Boolean {
        val appWidgetId = targetIntent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            return false
        }
        val uri = targetIntent?.data
        if (uri != null) {
            val uriWidgetId = uri.getQueryParameter("widgetId")?.toIntOrNull()
            if (!uri.isHierarchical ||
                uri.scheme != "easysubway" ||
                uri.host != "widget" ||
                uri.path != "/configure" ||
                uriWidgetId != appWidgetId
            ) {
                return false
            }
        }
        val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(appWidgetId) ?: return false
        return info.provider == ComponentName(this, NextTrainWidgetProvider::class.java)
    }

    override fun getDartEntrypointFunctionName(): String = "configureMain"
}
