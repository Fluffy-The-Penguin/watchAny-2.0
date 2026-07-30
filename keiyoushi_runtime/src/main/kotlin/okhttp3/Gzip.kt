package okhttp3

import okio.BufferedSource

object Gzip : CompressionInterceptor.DecompressionAlgorithm {
    override fun name(): String = "gzip"
    override fun decompress(source: BufferedSource): BufferedSource = source
}
