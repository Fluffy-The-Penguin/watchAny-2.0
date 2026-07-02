package eu.kanade.tachiyomi.network.interceptor

import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import java.util.concurrent.TimeUnit

class RateLimitInterceptor(
    private val permits: Int,
    private val period: Long = 1,
    private val unit: TimeUnit = TimeUnit.SECONDS,
) : Interceptor {
    private val lock = Any()
    private var nextRequestAt = 0L

    override fun intercept(chain: Interceptor.Chain): Response {
        synchronized(lock) {
            val now = System.currentTimeMillis()
            if (nextRequestAt > now) Thread.sleep(nextRequestAt - now)
            val interval = unit.toMillis(period).coerceAtLeast(1) / permits.coerceAtLeast(1)
            nextRequestAt = System.currentTimeMillis() + interval
        }
        return chain.proceed(chain.request())
    }
}

class SpecificHostRateLimitInterceptor(
    private val host: String,
    permits: Int,
    period: Long = 1,
    unit: TimeUnit = TimeUnit.SECONDS,
) : Interceptor {
    private val delegate = RateLimitInterceptor(permits, period, unit)

    override fun intercept(chain: Interceptor.Chain): Response {
        if (chain.request().url.host == host) return delegate.intercept(chain)
        return chain.proceed(chain.request())
    }
}

fun OkHttpClient.Builder.rateLimit(permits: Int, period: Long = 1, unit: TimeUnit = TimeUnit.SECONDS): OkHttpClient.Builder {
    return addInterceptor(RateLimitInterceptor(permits, period, unit))
}

fun OkHttpClient.Builder.rateLimitHost(host: String, permits: Int, period: Long = 1, unit: TimeUnit = TimeUnit.SECONDS): OkHttpClient.Builder {
    return addInterceptor(SpecificHostRateLimitInterceptor(host, permits, period, unit))
}
