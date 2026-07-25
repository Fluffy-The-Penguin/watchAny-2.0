package eu.kanade.tachiyomi.util

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import rx.Observable
import rx.Subscriber
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine


suspend fun <T> Observable<T>.awaitSingle(): T = suspendCancellableCoroutine { continuation ->
    val subscriber = object : Subscriber<T>() {
        private var valueEmitted = false

        override fun onNext(value: T) {
            valueEmitted = true
            if (continuation.isActive) {
                continuation.resume(value)
            }
        }

        override fun onError(error: Throwable) {
            if (continuation.isActive) {
                continuation.resumeWithException(error)
            }
        }

        override fun onCompleted() {
            if (!valueEmitted && continuation.isActive) {
                continuation.resumeWithException(NoSuchElementException("Observable completed without emitting a value"))
            }
        }
    }

    continuation.invokeOnCancellation { subscriber.unsubscribe() }
    subscribe(subscriber)
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
