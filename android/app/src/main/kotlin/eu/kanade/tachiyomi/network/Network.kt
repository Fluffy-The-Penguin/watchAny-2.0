@file:JvmName("RequestsKt")

package eu.kanade.tachiyomi.network

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.CacheControl
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.Buffer
import rx.Observable
import java.io.IOException
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor

open class NetworkHelper {
    open val client: OkHttpClient = unsafeClient()

    open val cloudflareClient: OkHttpClient get() = client
    open val defaultClient: OkHttpClient get() = client
    val defaultUserAgentProvider: () -> String = { DEFAULT_USER_AGENT }

    fun defaultUserAgentProvider(): String = defaultUserAgentProvider.invoke()


    companion object {
        const val DEFAULT_USER_AGENT = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"

        private class MemoryCookieJar : okhttp3.CookieJar {
            private val store = java.util.concurrent.ConcurrentHashMap<String, MutableList<okhttp3.Cookie>>()

            override fun saveFromResponse(url: okhttp3.HttpUrl, cookies: List<okhttp3.Cookie>) {
                val host = url.host
                val existing = store.getOrPut(host) { mutableListOf() }
                synchronized(existing) {
                    cookies.forEach { cookie ->
                        existing.removeAll { it.name == cookie.name }
                        existing.add(cookie)
                    }
                }
            }

            override fun loadForRequest(url: okhttp3.HttpUrl): List<okhttp3.Cookie> {
                val host = url.host
                val now = System.currentTimeMillis()
                val result = mutableListOf<okhttp3.Cookie>()
                store.entries.forEach { (domain, cookies) ->
                    if (host == domain || host.endsWith(".$domain")) {
                        synchronized(cookies) {
                            cookies.removeAll { it.expiresAt < now }
                            result.addAll(cookies)
                        }
                    }
                }
                return result
            }
        }

        private fun unsafeClient(): OkHttpClient {
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, arrayOf(trustManager), SecureRandom())
            return OkHttpClient.Builder()
                .addInterceptor(UncaughtExceptionInterceptor())
                .addInterceptor(UserAgentInterceptor())
                .addInterceptor(CloudflareInterceptor())
                .cookieJar(MemoryCookieJar())

                .sslSocketFactory(sslContext.socketFactory, trustManager)
                .hostnameVerifier { _, _ -> true }
                .followRedirects(true)
                .followSslRedirects(true)
                .callTimeout(45, TimeUnit.SECONDS)
                .addInterceptor { chain ->
                    val original = chain.request()
                    if (original.header("User-Agent").isNullOrBlank()) {
                        val request = original.newBuilder()
                            .header("User-Agent", DEFAULT_USER_AGENT)
                            .build()
                        chain.proceed(request)
                    } else {
                        chain.proceed(original)
                    }
                }
                .build()
        }


        private fun sanitizeJson(json: Any) {
            when (json) {
                is org.json.JSONObject -> {
                    if (json.has("pageProps")) {
                        val pageProps = json.optJSONObject("pageProps")
                        if (pageProps != null && pageProps.has("allSeries") && !pageProps.has("latestEntries")) {
                            pageProps.put("latestEntries", pageProps.get("allSeries"))
                        }
                    }
                    val keys = json.keys()
                    val keyList = ArrayList<String>()
                    while (keys.hasNext()) {
                        keyList.add(keys.next())
                    }
                    if (json.has("title") || json.has("name") || json.has("id") || json.has("series_id") || json.has("seriesId") || json.has("chapters") || json.has("series")) {
                        if (!json.has("altTitles")) {
                            json.put("altTitles", org.json.JSONArray())
                        }
                        if (!json.has("tags")) {
                            json.put("tags", org.json.JSONArray())
                        }
                        if (!json.has("views")) {
                            json.put("views", 0)
                        }
                        if (!json.has("series_id")) {
                            val idVal = json.opt("id") ?: json.opt("seriesId") ?: 0
                            val parsedId = when (idVal) {
                                is Number -> idVal
                                is String -> idVal.toIntOrNull() ?: idVal.toLongOrNull() ?: idVal
                                else -> idVal
                            }
                            json.put("series_id", parsedId)
                        }
                        if (!json.has("id")) {
                            val sidVal = json.opt("series_id") ?: json.opt("seriesId") ?: 0
                            val parsedId = when (sidVal) {
                                is Number -> sidVal
                                is String -> sidVal.toIntOrNull() ?: sidVal.toLongOrNull() ?: sidVal
                                else -> sidVal
                            }
                            json.put("id", parsedId)
                        }
                    }
                    for (key in keyList) {
                        val value = json.opt(key)
                        if (value != null) {
                            sanitizeJson(value)
                        }
                    }
                }
                is org.json.JSONArray -> {
                    for (i in 0 until json.length()) {
                        val value = json.opt(i)
                        if (value != null) {
                            sanitizeJson(value)
                        }
                    }
                }
            }
        }
    }
}

fun GET(url: String, headers: Headers = Headers.headersOf(), cache: CacheControl? = null): Request {
    val builder = Request.Builder().url(url).headers(headers).get()
    if (cache != null) builder.cacheControl(cache)
    return builder.build()
}

fun GET(url: String, headers: Headers = Headers.headersOf()): Request = GET(url, headers, null)

fun GET(url: HttpUrl, headers: Headers = Headers.headersOf(), cache: CacheControl? = null): Request {
    val builder = Request.Builder().url(url).headers(headers).get()
    if (cache != null) builder.cacheControl(cache)
    return builder.build()
}

fun POST(url: String, headers: Headers = Headers.headersOf(), body: RequestBody = RequestBody.create(null, ByteArray(0)), cache: CacheControl? = null): Request {
    val builder = Request.Builder().url(url).headers(headers).post(body)
    if (cache != null) builder.cacheControl(cache)
    return builder.build()
}

fun POST(url: HttpUrl, headers: Headers = Headers.headersOf(), body: RequestBody = RequestBody.create(null, ByteArray(0)), cache: CacheControl? = null): Request {
    val builder = Request.Builder().url(url).headers(headers).post(body)
    if (cache != null) builder.cacheControl(cache)
    return builder.build()
}

fun PUT(url: String, headers: Headers = Headers.headersOf(), body: RequestBody = RequestBody.create(null, ByteArray(0))): Request {
    return Request.Builder().url(url).headers(headers).put(body).build()
}

fun DELETE(url: String, headers: Headers = Headers.headersOf(), body: RequestBody? = null): Request {
    return Request.Builder().url(url).headers(headers).delete(body).build()
}

fun POST(url: String, headers: Headers = Headers.headersOf(), body: String): Request {
    return POST(url, headers, RequestBody.create("text/plain".toMediaTypeOrNull(), body))
}


