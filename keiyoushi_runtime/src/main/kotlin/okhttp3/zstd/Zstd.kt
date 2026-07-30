package okhttp3.zstd

import okhttp3.CompressionInterceptor
import okio.BufferedSource

object Zstd : CompressionInterceptor.DecompressionAlgorithm {
    override fun name(): String = "zstd"
    override fun decompress(source: BufferedSource): BufferedSource = source
}
