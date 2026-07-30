package android.content

import java.util.prefs.Preferences
import java.util.concurrent.CopyOnWriteArrayList

class SharedPreferencesImpl(private val nodeName: String) : SharedPreferences {
    private val prefs = Preferences.userRoot().node("keiyoushi_prefs/$nodeName")
    private val listeners = CopyOnWriteArrayList<SharedPreferences.OnSharedPreferenceChangeListener>()

    override fun getString(key: String, defValue: String?): String? {
        return prefs.get(key, defValue)
    }

    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? {
        val raw = prefs.get(key, null) ?: return defValues
        return raw.split("\u0000").toSet()
    }

    override fun getInt(key: String, defValue: Int): Int {
        return prefs.getInt(key, defValue)
    }

    override fun getLong(key: String, defValue: Long): Long {
        return prefs.getLong(key, defValue)
    }

    override fun getFloat(key: String, defValue: Float): Float {
        return prefs.getFloat(key, defValue)
    }

    override fun getBoolean(key: String, defValue: Boolean): Boolean {
        return prefs.getBoolean(key, defValue)
    }

    override fun contains(key: String): Boolean {
        return prefs.get(key, null) != null
    }

    override fun edit(): SharedPreferences.Editor = EditorImpl()

    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        listeners.add(listener)
    }

    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        listeners.remove(listener)
    }

    private inner class EditorImpl : SharedPreferences.Editor {
        private val changes = mutableMapOf<String, Any?>()
        private var clearAll = false

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            changes[key] = value
            return this
        }

        override fun putStringSet(key: String, values: Set<String>?): SharedPreferences.Editor {
            changes[key] = values?.joinToString("\u0000")
            return this
        }

        override fun putInt(key: String, value: Int): SharedPreferences.Editor {
            changes[key] = value
            return this
        }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor {
            changes[key] = value
            return this
        }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
            changes[key] = value
            return this
        }

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
            changes[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            changes[key] = this
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            clearAll = true
            return this
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearAll) {
                prefs.clear()
            }
            for ((key, value) in changes) {
                when (value) {
                    is String -> prefs.put(key, value)
                    is Int -> prefs.putInt(key, value)
                    is Long -> prefs.putLong(key, value)
                    is Float -> prefs.putFloat(key, value)
                    is Boolean -> prefs.putBoolean(key, value)
                    null -> prefs.remove(key)
                    else -> if (value === this) prefs.remove(key)
                }
                for (listener in listeners) {
                    listener.onSharedPreferenceChanged(this@SharedPreferencesImpl, key)
                }
            }
            prefs.flush()
        }
    }
}
