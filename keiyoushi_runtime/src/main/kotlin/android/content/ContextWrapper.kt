package android.content

open class ContextWrapper(val base: Context? = null) : Context() {
    fun getBaseContext(): Context? = base
}
