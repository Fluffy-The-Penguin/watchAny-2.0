package runtime;

import okhttp3.Interceptor;
import okhttp3.OkHttpClient;
import okhttp3.Response;
import java.io.IOException;

public class DummyInterceptors {

    public static class UncaughtExceptionInterceptor implements Interceptor {
        @Override
        public Response intercept(Chain chain) throws IOException {
            return chain.proceed(chain.request());
        }
    }

    public static class UserAgentInterceptor implements Interceptor {
        // Chrome on Android UA — bypasses Cloudflare basic bot detection
        private static final String UA =
            "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36";
        @Override
        public Response intercept(Chain chain) throws IOException {
            okhttp3.Request request = chain.request().newBuilder()
                .header("User-Agent", UA)
                .build();
            return chain.proceed(request);
        }
    }

    public static class CloudflareInterceptor implements Interceptor {
        @Override
        public Response intercept(Chain chain) throws IOException {
            return chain.proceed(chain.request());
        }
    }

    public static class IgnoreGzipInterceptor implements Interceptor {
        @Override
        public Response intercept(Chain chain) throws IOException {
            return chain.proceed(chain.request());
        }
    }

    public static class BrotliInterceptor implements Interceptor {
        @Override
        public Response intercept(Chain chain) throws IOException {
            return chain.proceed(chain.request());
        }
    }

    public static OkHttpClient addDummyInterceptors(OkHttpClient origClient) {
        if (origClient == null) {
            origClient = new OkHttpClient();
        }
        for (Interceptor i : origClient.interceptors()) {
            if ("CloudflareInterceptor".equals(i.getClass().getSimpleName())) {
                return origClient;
            }
        }
        return origClient.newBuilder()
                .addInterceptor(new UncaughtExceptionInterceptor())
                .addInterceptor(new UserAgentInterceptor())
                .addInterceptor(new CloudflareInterceptor())
                .addInterceptor(new IgnoreGzipInterceptor())
                .addInterceptor(new BrotliInterceptor())
                .build();
    }
}
