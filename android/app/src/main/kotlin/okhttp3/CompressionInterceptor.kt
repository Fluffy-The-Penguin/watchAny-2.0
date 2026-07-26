package okhttp3

import okio.BufferedSource

class CompressionInterceptor(vararg algorithms: DecompressionAlgorithm) : Interceptor {
    interface DecompressionAlgorithm {
        fun name(): String
        fun decompress(source: BufferedSource): BufferedSource
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        return chain.proceed(chain.request())
    }
}
