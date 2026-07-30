import eu.kanade.tachiyomi.source.model.SManga;
import eu.kanade.tachiyomi.source.model.SMangaImpl;
import eu.kanade.tachiyomi.source.online.HttpSource;
import runtime.DynamicExtensionPatcher;
import java.io.File;
import java.lang.reflect.Method;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Interceptor;
import okhttp3.Response;

public class TestAsuraDetails {
    public static void main(String[] args) throws Exception {
        System.out.println("=== Standalone Asura Scans Details Test ===");
        String appDataJarDir = System.getenv("APPDATA") + "\\com.example\\watch_any\\keiyoushi\\jar";
        File rawJar = new File(appDataJarDir, "tachiyomi-en.asurascans-v1.6.66.jar");
        System.out.println("Raw JAR: " + rawJar + " (exists: " + rawJar.exists() + ")");

        System.out.println("Patching JAR with DynamicExtensionPatcher...");
        File testJar = DynamicExtensionPatcher.patchJar(rawJar);
        System.out.println("Patched JAR: " + testJar.getAbsolutePath());

        java.net.URLClassLoader cl = new java.net.URLClassLoader(new java.net.URL[]{ testJar.toURI().toURL() }, TestAsuraDetails.class.getClassLoader());
        Class<?> extClass = cl.loadClass("eu.kanade.tachiyomi.extension.en.asurascans.ExtensionGenerated");
        HttpSource source = (HttpSource) extClass.getDeclaredConstructor().newInstance();
        System.out.println("Created source instance: " + source);

        try {
            OkHttpClient loggingClient = source.getClient().newBuilder()
                .addInterceptor(new Interceptor() {
                    @Override
                    public Response intercept(Chain chain) throws java.io.IOException {
                        Request req = chain.request();
                        System.out.println("--> HTTP Request: " + req.method() + " " + req.url());
                        System.out.println("    Headers: " + req.headers());
                        Response res = chain.proceed(req);
                        System.out.println("<-- HTTP Response: " + res.code() + " for " + req.url());
                        return res;
                    }
                })
                .build();

            // Set patched client on NetworkHelper
            java.lang.reflect.Field clientField = source.getNetwork().getClass().getDeclaredField("client");
            clientField.setAccessible(true);
            clientField.set(source.getNetwork(), loggingClient);
            System.out.println("Successfully injected HTTP logging interceptor into source!");
        } catch (Exception e) {
            System.out.println("Failed to inject client: " + e);
            e.printStackTrace();
        }

        SMangaImpl manga = new SMangaImpl();
        manga.setUrl("/comics/reformation-of-the-deadbeat-noble-f886a8af");
        manga.setTitle("Runtime Manga");

        try {
            Method getUrlMethod = extClass.getMethod("getMangaUrl", SManga.class);
            Object urlResult = getUrlMethod.invoke(source, manga);
            System.out.println("getMangaUrl returned: " + urlResult);
        } catch (Exception e) {
            System.out.println("getMangaUrl failed: " + e);
        }

        Method getMD = extClass.getMethod("getMangaDetails", SManga.class, kotlin.coroutines.Continuation.class);
        System.out.println("Calling getMangaDetails...");

        kotlin.coroutines.Continuation<Object> cont = new kotlin.coroutines.Continuation<Object>() {
            @Override
            public kotlin.coroutines.CoroutineContext getContext() {
                return kotlin.coroutines.EmptyCoroutineContext.INSTANCE;
            }
            @Override
            public void resumeWith(Object result) {
                System.out.println("=== ASYNC RESUME WITH CALLED! ===");
                System.out.println("Result class: " + (result == null ? "null" : result.getClass().getName()));
                if (result instanceof kotlin.Result.Failure) {
                    ((kotlin.Result.Failure) result).exception.printStackTrace();
                } else if (result instanceof SManga) {
                    SManga m = (SManga) result;
                    System.out.println("SUCCESS DETAILS: Title='" + m.getTitle() + "', Author='" + m.getAuthor() + "', Desc='" + (m.getDescription() != null ? m.getDescription().substring(0, Math.min(60, m.getDescription().length())) : "") + "', Status=" + m.getStatus());
                } else {
                    System.out.println("Other result: " + result);
                }
            }
        };

        Object syncRes = getMD.invoke(source, manga, cont);
        System.out.println("Sync return value: " + syncRes);

        // Sleep to let async network request finish
        Thread.sleep(8000);
    }
}
