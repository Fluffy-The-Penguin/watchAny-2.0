package scratch;

import runtime.PackageTools;
import eu.kanade.tachiyomi.source.CatalogueSource;
import eu.kanade.tachiyomi.source.model.MangasPage;
import rx.Observable;

import java.io.File;

public class TestAsuraStack {
    public static void main(String[] args) {
        try {
            File jarFile = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.asurascans-v1.6.66.jar");
            System.out.println("Loading Asura Scans...");
            Object ext = PackageTools.INSTANCE.loadExtensionClass(jarFile.toPath(), "eu.kanade.tachiyomi.extension.en.asurascans.ExtensionGenerated");
            System.out.println("Loaded Asura: " + ext);

            CatalogueSource source = (CatalogueSource) ext;
            System.out.println("Calling fetchPopularManga(1)...");
            Observable<MangasPage> obs = source.fetchPopularManga(1);
            System.out.println("Subscribing to observable...");
            MangasPage page = obs.toBlocking().first();
            System.out.println("SUCCESS! Mangas count: " + page.getMangas().size());
            for (var m : page.getMangas()) {
                System.out.println(" - " + m.getTitle() + " (" + m.getUrl() + ")");
            }
        } catch (Throwable t) {
            System.out.println("CAUGHT EXCEPTION: " + t);
            t.printStackTrace(System.out);
        }
    }
}
