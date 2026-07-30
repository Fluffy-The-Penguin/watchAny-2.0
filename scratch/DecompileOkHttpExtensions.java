package scratch;

import java.lang.reflect.Method;

public class DecompileOkHttpExtensions {
    public static void main(String[] args) {
        try {
            Class<?> clazz = Class.forName("eu.kanade.tachiyomi.network.OkHttpExtensionsKt");
            System.out.println("--- OkHttpExtensionsKt methods ---");
            for (Method m : clazz.getDeclaredMethods()) {
                System.out.println(m.getName() + " " + java.lang.reflect.Modifier.toString(m.getModifiers()) + " " + m.getReturnType().getName() + " " + java.util.Arrays.toString(m.getParameterTypes()));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
