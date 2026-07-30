package okhttp3.brotli

import okhttp3.Interceptor
import okhttp3.Response

class BrotliInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        return chain.proceed(chain.request())
    }

    companion object {
        @JvmField
        val INSTANCE = BrotliInterceptor()
    }
}
