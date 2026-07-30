package android.net

import java.net.URI
import java.net.URLEncoder
import java.net.URLDecoder

class Uri private constructor(private val uriString: String) {
    private val parsed: URI? = try { URI(uriString) } catch (_: Exception) { null }

    fun getHost(): String? = parsed?.host
    fun getPath(): String? = parsed?.path
    fun getScheme(): String? = parsed?.scheme

    fun getQueryParameter(key: String): String? {
        val query = parsed?.query ?: return null
        for (param in query.split("&")) {
            val parts = param.split("=")
            if (parts.isNotEmpty() && URLDecoder.decode(parts[0], "UTF-8") == key) {
                return if (parts.size > 1) URLDecoder.decode(parts[1], "UTF-8") else ""
            }
        }
        return null
    }

    override fun toString(): String = uriString

    companion object {
        @JvmStatic fun parse(uriString: String): Uri = Uri(uriString)
        @JvmStatic fun encode(s: String): String = URLEncoder.encode(s, "UTF-8")
        @JvmStatic fun decode(s: String): String = URLDecoder.decode(s, "UTF-8")
    }
}
