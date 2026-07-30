package android.preference

import android.content.Context
import android.content.SharedPreferences

object PreferenceManager {
    @JvmStatic
    fun getDefaultSharedPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences("default", 0)
    }
}
