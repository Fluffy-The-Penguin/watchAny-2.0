package eu.kanade.tachiyomi.network

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.CacheControl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.Buffer
import rx.Observable
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

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
