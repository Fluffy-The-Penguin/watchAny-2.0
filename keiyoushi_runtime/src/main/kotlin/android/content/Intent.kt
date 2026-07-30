package android.content

open class Intent {
    fun putExtra(name: String, value: String?): Intent = this
    fun putExtra(name: String, value: Boolean): Intent = this
    fun putExtra(name: String, value: Int): Intent = this
    fun getStringExtra(name: String): String? = null
    fun getBooleanExtra(name: String, defaultValue: Boolean): Boolean = defaultValue
    fun getIntExtra(name: String, defaultValue: Int): Int = defaultValue
}
