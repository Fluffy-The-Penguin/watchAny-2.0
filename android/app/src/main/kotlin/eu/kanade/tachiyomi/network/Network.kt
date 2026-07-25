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

class NetworkHelper {
    val client: OkHttpClient = unsafeClient()

    val cloudflareClient: OkHttpClient = client
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
                .cookieJar(MemoryCookieJar())
                .sslSocketFactory(sslContext.socketFactory, trustManager)
                .hostnameVerifier { _, _ -> true }
                .followRedirects(true)
                .followSslRedirects(true)
                .callTimeout(45, TimeUnit.SECONDS)
                .addInterceptor { chain ->
                    val original = chain.request()
                    val builder = original.newBuilder()
                    if (original.header("User-Agent").isNullOrBlank() || original.header("User-Agent")?.contains("Windows") == true) {
                        builder.header("User-Agent", DEFAULT_USER_AGENT)
                    }
                    if (original.header("Accept-Language").isNullOrBlank()) {
                        builder.header("Accept-Language", "en-US,en;q=0.9")
                    }
                    if (original.header("Sec-Ch-Ua").isNullOrBlank()) {
                        builder.header("Sec-Ch-Ua", "\"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\", \"Google Chrome\";v=\"125\"")
                    }
                    if (original.header("Sec-Ch-Ua-Mobile").isNullOrBlank()) {
                        builder.header("Sec-Ch-Ua-Mobile", "?1")
                    }
                    if (original.header("Sec-Ch-Ua-Platform").isNullOrBlank()) {
                        builder.header("Sec-Ch-Ua-Platform", "\"Android\"")
                    }
                    val request = builder.build()
                    val response = chain.proceed(request)
                    val host = request.url.host.lowercase(java.util.Locale.US)
                    if ((host.contains("flamecomics") || host.contains("asura")) && response.isSuccessful) {
                        val body = response.body
                        if (body != null) {
                            var bodyString: String? = null
                            try {
                                bodyString = body.string()
                                var modifiedBodyString = bodyString
                                val trimmed = bodyString.trim()
                                if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
                                    val root = org.json.JSONTokener(bodyString).nextValue()
                                    sanitizeJson(root)
                                    modifiedBodyString = root.toString()
                                } else if (bodyString.contains("__NEXT_DATA__")) {
                                    val regex = Regex("""(<script\s+[^>]*id=["']__NEXT_DATA__['"][^>]*>)(.*?)(</script>)""", RegexOption.DOT_MATCHES_ALL)
                                    val match = regex.find(bodyString)
                                    if (match != null) {
                                        val prefix = match.groupValues[1]
                                        val jsonStr = match.groupValues[2]
                                        val suffix = match.groupValues[3]
                                        try {
                                            val root = org.json.JSONTokener(jsonStr).nextValue()
                                            sanitizeJson(root)
                                            val sanitizedJsonStr = root.toString()
                                            modifiedBodyString = bodyString.replace(match.value, prefix + sanitizedJsonStr + suffix)
                                        } catch (e: Throwable) {
                                            android.util.Log.e("watchAny-Network", "Failed to sanitize script json: ${e.message}")
                                        }
                                    }
                                }
                                val newBody = okhttp3.ResponseBody.create(body.contentType(), modifiedBodyString)
                                return@addInterceptor response.newBuilder().body(newBody).build()
                            } catch (e: Throwable) {
                                if (bodyString != null) {
                                    val newBody = okhttp3.ResponseBody.create(body.contentType(), bodyString)
                                    return@addInterceptor response.newBuilder().body(newBody).build()
                                }
                            }
                        }
                    }
                    response
                }
                .build()
        }


        private fun sanitizeJson(json: Any) {
            when (json) {
                is org.json.JSONObject -> {
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


