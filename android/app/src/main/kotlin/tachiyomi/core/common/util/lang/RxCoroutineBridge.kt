package tachiyomi.core.common.util.lang

import kotlinx.coroutines.suspendCancellableCoroutine
import rx.Observable
import rx.Subscriber
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

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



