package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class CleanPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_clean.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("runtime/SourceLoadError.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("<init>".equals(mn.name)) {
                            InsnList list = mn.instructions;
                            InsnList clean = new InsnList();
                            for (AbstractInsnNode ain : list) {
                                if (ain.getOpcode() == Opcodes.GETSTATIC) {
                                    FieldInsnNode fin = (FieldInsnNode) ain;
                                    if ("java/lang/System".equals(fin.owner) && "err".equals(fin.name)) {
                                        continue;
                                    }
                                }
                                clean.add(ain);
                            }
                        }
                    }

                    ClassWriter cw = new ClassWriter(0);
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
        System.out.println("Cleaned SourceLoadError in assets/bin/keiyoushi-runtime.jar successfully!");
    }
}
