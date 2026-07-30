package android.webkit

import java.net.URLConnection

class MimeTypeMap private constructor() {
    fun getFileExtensionFromUrl(url: String): String {
        val u = url.substringBefore('?').substringBefore('#')
        return u.substringAfterLast('.', "")
    }

    fun getMimeTypeFromExtension(extension: String): String? {
        return URLConnection.guessContentTypeFromName("file.$extension")
    }

    companion object {
        private val INSTANCE = MimeTypeMap()
        @JvmStatic fun getSingleton(): MimeTypeMap = INSTANCE
    }
}
