package scratch;

import java.io.File;
import java.util.Enumeration;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.tree.ClassNode;

public class DebugFlame {
    public static void main(String[] args) {
        try {
            File jarFile = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.flamecomics-v1.4.50.jar");
            JarFile jar = new JarFile(jarFile);
            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                if (entry.getName().endsWith("y.class")) {
                    System.out.println("Found entry: " + entry.getName());
                    ClassReader cr = new ClassReader(jar.getInputStream(entry));
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);
                    System.out.println("Class name: " + cn.name + " | superName: " + cn.superName + " | interfaces: " + cn.interfaces);
                }
            }
        } catch (Throwable t) {
            t.printStackTrace();
        }
    }
}
