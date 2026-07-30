package okhttp3;

import java.io.IOException;

public class CompressionInterceptor implements Interceptor {

    public enum DecompressionAlgorithm {
        BROTLI,
        GZIP,
        ZSTD
    }

    public CompressionInterceptor(DecompressionAlgorithm... algorithms) {}

    @Override
    public Response intercept(Chain chain) throws IOException {
        return chain.proceed(chain.request());
    }
}
