package scratch;

import java.lang.reflect.Method;
import eu.kanade.tachiyomi.source.CatalogueSource;
import eu.kanade.tachiyomi.source.online.HttpSource;

public class DecompileSource {
    public static void main(String[] args) {
        System.out.println("--- CatalogueSource methods ---");
        for (Method m : CatalogueSource.class.getDeclaredMethods()) {
            System.out.println(m.getName() + " " + java.lang.reflect.Modifier.toString(m.getModifiers()) + " " + m.getReturnType().getSimpleName() + " " + java.util.Arrays.toString(m.getParameterTypes()));
        }
        System.out.println("--- HttpSource methods ---");
        for (Method m : HttpSource.class.getDeclaredMethods()) {
            System.out.println(m.getName() + " " + java.lang.reflect.Modifier.toString(m.getModifiers()) + " " + m.getReturnType().getSimpleName() + " " + java.util.Arrays.toString(m.getParameterTypes()));
        }
    }
}
