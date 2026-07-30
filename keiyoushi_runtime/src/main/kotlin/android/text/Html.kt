package android.text

object Html {
    @JvmStatic
    fun fromHtml(source: String): String {
        return source.replace(Regex("<[^>]*>"), "")
    }

    @JvmStatic
    fun fromHtml(source: String, flags: Int): String {
        return fromHtml(source)
    }
}
