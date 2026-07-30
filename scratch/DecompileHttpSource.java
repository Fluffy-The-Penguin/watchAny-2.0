package scratch;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.InputStream;
import java.util.jar.JarFile;

public class DecompileHttpSource {
    public static void main(String[] args) throws Exception {
        String jarPath = "assets/bin/keiyoushi-runtime.jar";
        try (JarFile jar = new JarFile(jarPath)) {
            InputStream is = jar.getInputStream(jar.getJarEntry("eu/kanade/tachiyomi/source/online/HttpSource.class"));
            ClassReader cr = new ClassReader(is);
            ClassNode cn = new ClassNode();
            cr.accept(cn, 0);

            System.out.println("Methods in HttpSource:");
            for (MethodNode mn : cn.methods) {
                System.out.println(" - " + mn.name + mn.desc);
            }
            System.out.println("Fields in HttpSource:");
            for (FieldNode fn : cn.fields) {
                System.out.println(" - " + fn.name + " desc=" + fn.desc);
            }
        }
    }
}
