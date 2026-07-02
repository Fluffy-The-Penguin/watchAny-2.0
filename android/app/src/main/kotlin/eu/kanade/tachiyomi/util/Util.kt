@file:JvmName("JsoupExtensionsKt")

package eu.kanade.tachiyomi.util

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import rx.Observable
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

suspend fun <T> Observable<T>.awaitSingle(): T = suspendCoroutine { continuation ->
    subscribe(
        { value -> continuation.resume(value) },
        { error -> continuation.resumeWithException(error) },
    )
}

fun Response.asJsoup(html: String? = null): Document {
    val bodyText = html ?: body.string()
    return Jsoup.parse(bodyText, request.url.toString())
}

suspend fun <T> withIOContext(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }

suspend fun <T> Observable<T>.awaitFirst(): T = suspendCoroutine { continuation ->
    var resumed = false
    subscribe(
        { value ->
            if (!resumed) {
                resumed = true
                continuation.resume(value)
            }
        },
        { error -> if (!resumed) continuation.resumeWithException(error) },
    )
}
