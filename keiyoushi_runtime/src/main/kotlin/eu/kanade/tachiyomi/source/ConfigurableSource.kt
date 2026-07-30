package eu.kanade.tachiyomi.source

import android.content.SharedPreferences

interface ConfigurableSource {
    fun setupPreferenceScreen(screen: Any) {}
}

interface UnmeteredSource
