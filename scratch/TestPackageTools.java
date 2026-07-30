package scratch;
import runtime.PackageTools;
import runtime.DynamicExtensionPatcher;
import java.io.File;
import java.nio.file.Path;

public class TestPackageTools {
    public static void main(String[] args) {
        try {
            File jarAsura = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.asurascans-v1.6.66.jar");
            Object instAsura = PackageTools.INSTANCE.loadExtensionClass(jarAsura.toPath(), "eu.kanade.tachiyomi.extension.en.asurascans.ExtensionGenerated");
            System.out.println("Asura loaded: " + instAsura);

            File jarFlame = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.flamecomics-v1.4.50.jar");
            Object instFlame = PackageTools.INSTANCE.loadExtensionClass(jarFlame.toPath(), "eu.kanade.tachiyomi.extension.en.flamecomics.ExtensionGenerated");
            System.out.println("Flame loaded: " + instFlame);
        } catch (Throwable t) {
            t.printStackTrace();
        }
    }
}
