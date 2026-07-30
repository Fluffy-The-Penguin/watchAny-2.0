package eu.kanade.tachiyomi.network.interceptor

import okhttp3.Interceptor
import okhttp3.Response

class UserAgentInterceptor(val userAgent: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val builder = original.newBuilder()
        if (original.header("User-Agent") == null) {
            builder.header("User-Agent", userAgent)
        }
        if (original.header("Accept") == null) {
            builder.header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        }
        if (original.header("Accept-Language") == null) {
            builder.header("Accept-Language", "en-US,en;q=0.9")
        }
        if (original.header("Referer") == null) {
            val origin = original.url.scheme + "://" + original.url.host + "/"
            builder.header("Referer", origin)
        }
        val req = builder.build()
        println("[OkHttp Request] ${req.method} ${req.url}")
        return chain.proceed(req)
    }
}
