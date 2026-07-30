package scratch;

import java.io.File;
import java.net.URL;
import runtime.ChildFirstURLClassLoader;
import runtime.DynamicExtensionPatcher;

public class TestAsura {
    public static void main(String[] args) {
        try {
            File origJar = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.flamecomics-v1.4.50.jar");
            File patchedJar = DynamicExtensionPatcher.getPatchedJarFile(origJar);

            System.out.println("Patched jar path: " + patchedJar.getAbsolutePath());

            URL url = patchedJar.toURI().toURL();

            ChildFirstURLClassLoader loader = new ChildFirstURLClassLoader(new URL[]{url}, TestAsura.class.getClassLoader());

            System.out.println("Loading ExtensionGenerated...");
            Class<?> extClass = loader.loadClass("eu.kanade.tachiyomi.extension.en.flamecomics.ExtensionGenerated");
            System.out.println("Loaded ExtensionGenerated: " + extClass);

            Object inst = extClass.getDeclaredConstructor().newInstance();
            System.out.println("Instantiated ExtensionGenerated successfully: " + inst);

        } catch (Throwable t) {
            printDetailedStackTrace(t);
        }
    }

    private static void printDetailedStackTrace(Throwable t) {
        System.err.println("Exception: " + t.getClass().getName() + ": " + t.getMessage());
        StackTraceElement[] elements = t.getStackTrace();
        for (int i = 0; i < Math.min(30, elements.length); i++) {
            System.err.println("\tat " + elements[i]);
        }
        if (t.getCause() != null) {
            System.err.println("Caused by:");
            printDetailedStackTrace(t.getCause());
        }
    }
}
