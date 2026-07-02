package tachiyomi.core.common.util.lang

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
