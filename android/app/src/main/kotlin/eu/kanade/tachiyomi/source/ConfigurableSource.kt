package eu.kanade.tachiyomi.source

import android.content.Context
import androidx.preference.PreferenceScreen

interface ConfigurableSource : Source {
    fun setupPreferenceScreen(screen: PreferenceScreen)

    @Deprecated("Use setupPreferenceScreen(screen) instead")
    fun setupPreferenceScreen(screen: PreferenceScreen, context: Context) = setupPreferenceScreen(screen)
}
