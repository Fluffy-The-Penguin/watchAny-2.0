package okhttp3.brotli

import okhttp3.CompressionInterceptor
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import okio.BufferedSource

object Brotli : Interceptor, CompressionInterceptor.DecompressionAlgorithm {
    override fun name(): String = "br"

    override fun decompress(source: BufferedSource): BufferedSource = source

    override fun intercept(chain: Interceptor.Chain): Response {
        return BrotliInterceptor.INSTANCE.intercept(chain)
    }

    fun OkHttpClient.Builder.brotli(): OkHttpClient.Builder {
        return this.addInterceptor(Brotli as Interceptor)
    }
}
