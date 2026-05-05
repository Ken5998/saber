package com.adilhanney.saber

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class RecentNotesWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        Log.d("SaberWidget", "onUpdate called for ${appWidgetIds.size} widgets")
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val RECENT_FILES_KEY = "flutter.recentFiles"
        private const val MAX_NOTES = 5

        private val NOTE_IDS = listOf(
            R.id.note_0, R.id.note_1, R.id.note_2, R.id.note_3, R.id.note_4,
        )

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            Log.d("SaberWidget", "updateWidget called for id=$appWidgetId")
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_recent_notes)

                val openAppIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openAppPending = PendingIntent.getActivity(
                    context, 0, openAppIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_title, openAppPending)

                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val allKeys = prefs.all.keys.toList()
                Log.d("SaberWidget", "SharedPrefs keys: $allKeys")

                val recentFilesRaw = prefs.getString(RECENT_FILES_KEY, null)
                Log.d("SaberWidget", "recentFilesRaw: $recentFilesRaw")

                // Flutter prefixes list values with a base64 marker ending in "!"
                // We need to strip everything up to and including the "!" character
                val recentFilesJson = recentFilesRaw?.let {
                    val markerIndex = it.indexOf('!')
                    if (markerIndex >= 0) it.substring(markerIndex + 1) else it
                }
                Log.d("SaberWidget", "recentFilesJson cleaned: $recentFilesJson")

                val recentFiles = mutableListOf<String>()
                if (recentFilesJson != null) {
                    try {
                        val arr = JSONArray(recentFilesJson)
                        for (i in 0 until arr.length()) {
                            val path = arr.getString(i)
                            if (!path.endsWith(".quill.json") && !path.endsWith(".web.json")) {
                                recentFiles.add(path)
                                if (recentFiles.size >= MAX_NOTES) break
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("SaberWidget", "Error parsing recentFiles: $e")
                    }
                }

                Log.d("SaberWidget", "recentFiles count: ${recentFiles.size}")

                for (i in NOTE_IDS.indices) {
                    val viewId = NOTE_IDS[i]
                    if (i < recentFiles.size) {
                        val path = recentFiles[i]
                        val name = path.substringAfterLast('/')
                            .removeSuffix(".sbn2")
                            .removeSuffix(".sbn")
                        views.setViewVisibility(viewId, View.VISIBLE)
                        views.setTextViewText(viewId, "✏️  $name")
                        val noteIntent = Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            putExtra("notePath", path)
                        }
                        val notePending = PendingIntent.getActivity(
                            context, i + 1, noteIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                        views.setOnClickPendingIntent(viewId, notePending)
                    } else {
                        views.setViewVisibility(viewId, View.INVISIBLE)
                    }
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
                Log.d("SaberWidget", "Widget updated successfully")
            } catch (e: Exception) {
                Log.e("SaberWidget", "Error updating widget: $e")
            }
        }
    }
}
