package android.content

import java.io.File

open class Context {
    open fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
        return SharedPreferencesImpl(name)
    }

    open fun getPackageName(): String = "eu.kanade.tachiyomi"
    open fun getApplicationContext(): Context = this
    open fun getSystemService(name: String): Any? = null
    open fun getString(resId: Int): String = ""
    open fun getCacheDir(): File = File(System.getProperty("java.io.tmpdir"), "keiyoushi_cache").apply { mkdirs() }
    open fun getFilesDir(): File = File(System.getProperty("user.home"), ".keiyoushi/files").apply { mkdirs() }
}
