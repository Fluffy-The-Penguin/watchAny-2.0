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
        const val DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

        private fun unsafeClient(): OkHttpClient {
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, arrayOf(trustManager), SecureRandom())
            return OkHttpClient.Builder()
                .sslSocketFactory(sslContext.socketFactory, trustManager)
                .hostnameVerifier { _, _ -> true }
                .followRedirects(true)
                .followSslRedirects(true)
                .callTimeout(45, TimeUnit.SECONDS)
                .build()
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


