package scratch;

import java.io.File;

public class TestFlameStack {
    public static void main(String[] args) {
        try {
            File flameFile = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.flamecomics-v1.4.50.jar");
            Object ext = runtime.PackageTools.INSTANCE.loadExtensionClass(flameFile.toPath(), "eu.kanade.tachiyomi.extension.en.flamecomics.ExtensionGenerated");
            System.out.println("Flame loaded successfully: " + ext);
        } catch (Throwable t) {
            Throwable cause = t;
            while (cause.getCause() != null) {
                cause = cause.getCause();
            }
            StackTraceElement[] frames = cause.getStackTrace();
            System.out.println("Exception: " + cause);
            for (int i = 0; i < Math.min(40, frames.length); i++) {
                System.out.println("    at " + frames[i]);
            }
        }
    }
}
