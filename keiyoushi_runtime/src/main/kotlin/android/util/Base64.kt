package android.util

import java.util.Base64 as JavaBase64

object Base64 {
    const val DEFAULT = 0
    const val NO_PADDING = 1
    const val NO_WRAP = 2
    const val CRLF = 4
    const val URL_SAFE = 8

    @JvmStatic
    fun encodeToString(input: ByteArray, flags: Int): String {
        return if ((flags and URL_SAFE) != 0) {
            JavaBase64.getUrlEncoder().encodeToString(input)
        } else {
            JavaBase64.getEncoder().encodeToString(input)
        }
    }

    @JvmStatic
    fun decode(str: String, flags: Int): ByteArray {
        return if ((flags and URL_SAFE) != 0) {
            JavaBase64.getUrlDecoder().decode(str)
        } else {
            JavaBase64.getDecoder().decode(str)
        }
    }
}
