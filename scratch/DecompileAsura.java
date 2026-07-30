package scratch;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.InputStream;
import java.util.jar.JarFile;

public class DecompileAsura {
    public static void main(String[] args) throws Exception {
        String jarPath = "C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.asurascans-v1.6.66.jar";
        try (JarFile jar = new JarFile(jarPath)) {
            InputStream is = jar.getInputStream(jar.getJarEntry("c1.class"));
            ClassReader cr = new ClassReader(is);
            ClassNode cn = new ClassNode();
            cr.accept(cn, 0);

            System.out.println("Class c1 super: " + cn.superName + " interfaces: " + cn.interfaces);
            for (FieldNode fn : cn.fields) {
                System.out.println("Field: " + fn.name + " desc=" + fn.desc + " access=" + fn.access);
            }
            for (MethodNode mn : cn.methods) {
                System.out.println("Method: " + mn.name + mn.desc);
            }
        }
    }
}
