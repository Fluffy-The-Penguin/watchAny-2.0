package tachiyomi.core.common.util.lang

import rx.Observable
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

suspend fun <T> Observable<T>.awaitSingle(): T = suspendCoroutine { continuation ->
    var isResumed = false
    var hasValue = false
    subscribe(
        { value ->
            if (!isResumed) {
                isResumed = true
                hasValue = true
                continuation.resume(value)
            }
        },
        { error ->
            if (!isResumed) {
                isResumed = true
                continuation.resumeWithException(error)
            }
        },
        {
            if (!isResumed && !hasValue) {
                isResumed = true
                continuation.resumeWithException(NoSuchElementException("Observable completed empty"))
            }
        }
    )
}

