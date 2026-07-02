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

fun Call.asObservableSuccess(): Observable<Response> = Observable.create { subscriber ->
    try {
        val response = execute()
        if (!response.isSuccessful) {
            val message = unsuccessfulResponseMessage(response)
            response.close()
            throw IOException(message)
        }
        if (!subscriber.isUnsubscribed) {
            subscriber.onNext(response)
            subscriber.onCompleted()
        }
    } catch (error: Throwable) {
        if (!subscriber.isUnsubscribed) subscriber.onError(error)
    }
}

suspend fun Call.awaitSuccess(): Response = suspendCancellableCoroutine { continuation ->
    enqueue(object : okhttp3.Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (continuation.isCancelled) return
            continuation.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            if (!response.isSuccessful) {
                val message = unsuccessfulResponseMessage(response)
                response.close()
                continuation.resumeWithException(IOException(message))
                return
            }
            continuation.resume(response)
        }
    })
    continuation.invokeOnCancellation { cancel() }
}

private fun unsuccessfulResponseMessage(response: Response): String {
    val url = response.request.url
    val cloudflareChallenge = response.header("Cf-Mitigated").equals("challenge", ignoreCase = true)
    if (cloudflareChallenge) {
        return "Cloudflare challenge for $url. This source requires a browser/WebView challenge solver; use another source or retry later."
    }
    return "HTTP ${response.code} for $url"
}

fun OkHttpClient.newCachelessCallWithProgress(request: Request, listener: ProgressListener): Call {
    return newCall(request.newBuilder().cacheControl(CacheControl.FORCE_NETWORK).build())
}

interface ProgressListener {
    fun update(bytesRead: Long, contentLength: Long, done: Boolean)
}

fun String.toHttpUrlOrNullCompat() = runCatching { toHttpUrl() }.getOrNull()

fun String.toRequestBody(contentType: String = "text/plain"): RequestBody {
    return RequestBody.create(contentType.toMediaTypeOrNull(), this)
}

fun ByteArray.toRequestBody(contentType: String = "application/octet-stream"): RequestBody {
    return RequestBody.create(contentType.toMediaTypeOrNull(), this)
}

fun RequestBody.readUtf8(): String {
    val buffer = Buffer()
    writeTo(buffer)
    return buffer.readUtf8()
}
