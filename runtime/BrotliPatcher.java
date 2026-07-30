package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class BrotliPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_brotli.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("okhttp3/brotli/BrotliInterceptor.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("intercept".equals(mn.name)) {
                            for (AbstractInsnNode ain : mn.instructions) {
                                if (ain.getOpcode() == Opcodes.LDC) {
                                    LdcInsnNode ldc = (LdcInsnNode) ain;
                                    if ("br,gzip".equals(ldc.cst)) {
                                        ldc.cst = "gzip";
                                        System.out.println("Patched BrotliInterceptor Accept-Encoding from 'br,gzip' to 'gzip'!");
                                    }
                                }
                            }
                        }
                    }

                    ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
                    cn.accept(cw);
                    bytes = cw.toByteArray();
                }

                JarEntry newEntry = new JarEntry(entry.getName());
                jos.putNextEntry(newEntry);
                jos.write(bytes);
                jos.closeEntry();
            }
        }

        Files.move(tempFile.toPath(), jarFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with BrotliPatcher successfully!");
    }
}
