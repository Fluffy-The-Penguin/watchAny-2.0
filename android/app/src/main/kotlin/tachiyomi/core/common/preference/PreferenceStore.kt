package tachiyomi.core.common.preference

import android.content.Context
import android.content.SharedPreferences

interface PreferenceStore {
    fun getString(key: String, defaultValue: String = ""): Preference<String>
    fun getLong(key: String, defaultValue: Long = 0L): Preference<Long>
    fun getInt(key: String, defaultValue: Int = 0): Preference<Int>
    fun getBoolean(key: String, defaultValue: Boolean = false): Preference<Boolean>
    fun getStringSet(key: String, defaultValue: Set<String> = emptySet()): Preference<Set<String>>
    fun getAll(): Map<String, *>
}

interface Preference<T> {
    fun key(): String
    fun get(): T
    fun set(value: T)
    fun isSet(): Boolean
    fun delete()
    fun defaultValue(): T
}

class AndroidPreferenceStore(private val context: Context) : PreferenceStore {
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("eu.kanade.tachiyomi_preferences", Context.MODE_PRIVATE)
    }

    override fun getString(key: String, defaultValue: String): Preference<String> =
        AndroidPreference(prefs, key, defaultValue, PreferenceType.STRING)

    override fun getLong(key: String, defaultValue: Long): Preference<Long> =
        AndroidPreference(prefs, key, defaultValue, PreferenceType.LONG)

    override fun getInt(key: String, defaultValue: Int): Preference<Int> =
        AndroidPreference(prefs, key, defaultValue, PreferenceType.INT)

    override fun getBoolean(key: String, defaultValue: Boolean): Preference<Boolean> =
        AndroidPreference(prefs, key, defaultValue, PreferenceType.BOOLEAN)

    override fun getStringSet(key: String, defaultValue: Set<String>): Preference<Set<String>> =
        AndroidPreference(prefs, key, defaultValue, PreferenceType.STRING_SET)

    override fun getAll(): Map<String, *> = prefs.all
}

private enum class PreferenceType { STRING, LONG, INT, BOOLEAN, STRING_SET }

private class AndroidPreference<T>(
    private val prefs: SharedPreferences,
    private val key: String,
    private val defaultValue: T,
    private val type: PreferenceType
) : Preference<T> {
    override fun key(): String = key
    override fun defaultValue(): T = defaultValue

    @Suppress("UNCHECKED_CAST")
    override fun get(): T {
        if (!prefs.contains(key)) return defaultValue
        return when (type) {
            PreferenceType.STRING -> (prefs.getString(key, defaultValue as? String ?: "") ?: defaultValue) as T
            PreferenceType.LONG -> (prefs.getLong(key, defaultValue as? Long ?: 0L)) as T
            PreferenceType.INT -> (prefs.getInt(key, defaultValue as? Int ?: 0)) as T
            PreferenceType.BOOLEAN -> (prefs.getBoolean(key, defaultValue as? Boolean ?: false)) as T
            PreferenceType.STRING_SET -> (prefs.getStringSet(key, defaultValue as? Set<String> ?: emptySet()) ?: defaultValue) as T
        }
    }

    @Suppress("UNCHECKED_CAST")
    override fun set(value: T) {
        val editor = prefs.edit()
        when (type) {
            PreferenceType.STRING -> editor.putString(key, value as String)
            PreferenceType.LONG -> editor.putLong(key, value as Long)
            PreferenceType.INT -> editor.putInt(key, value as Int)
            PreferenceType.BOOLEAN -> editor.putBoolean(key, value as Boolean)
            PreferenceType.STRING_SET -> editor.putStringSet(key, value as Set<String>)
        }
        editor.apply()
    }

    override fun isSet(): Boolean = prefs.contains(key)
    override fun delete() { prefs.edit().remove(key).apply() }
}
