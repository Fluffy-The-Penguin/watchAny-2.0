package eu.kanade.tachiyomi.network

import okhttp3.CacheControl
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.Request
import okhttp3.RequestBody

private val DEFAULT_HEADERS = Headers.headersOf()
private val DEFAULT_BODY = RequestBody.create(null, ByteArray(0))

fun GET(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    cacheControl: CacheControl? = null
): Request {
    val builder = Request.Builder()
        .url(url)
        .headers(headers)
    if (cacheControl != null) {
        builder.cacheControl(cacheControl)
    }
    return builder.build()
}

fun GET(
    url: HttpUrl,
    headers: Headers = DEFAULT_HEADERS,
    cacheControl: CacheControl? = null
): Request {
    return GET(url.toString(), headers, cacheControl)
}

fun POST(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cacheControl: CacheControl? = null
): Request {
    val builder = Request.Builder()
        .url(url)
        .headers(headers)
        .post(body)
    if (cacheControl != null) {
        builder.cacheControl(cacheControl)
    }
    return builder.build()
}

fun POST(
    url: HttpUrl,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cacheControl: CacheControl? = null
): Request {
    return POST(url.toString(), headers, body, cacheControl)
}
