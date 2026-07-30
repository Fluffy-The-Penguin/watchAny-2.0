package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class FlamePatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.flamecomics-v1.4.50.jar");
        File tempFile = new File(jarFile.getAbsolutePath() + ".tmp");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("eu/kanade/tachiyomi/extension/en/flamecomics/ExtensionGenerated.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("c".equals(mn.name) && "()Lkotlinx/serialization/json/Json;".equals(mn.desc)) {
                            InsnList il = new InsnList();
                            LabelNode lblNotNull = new LabelNode();

                            il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                            il.add(new FieldInsnNode(Opcodes.GETFIELD, "eu/kanade/tachiyomi/extension/en/flamecomics/ExtensionGenerated", "c", "Lkotlin/Lazy;"));
                            il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, "kotlin/Lazy", "getValue", "()Ljava/lang/Object;", true));
                            il.add(new TypeInsnNode(Opcodes.CHECKCAST, "kotlinx/serialization/json/Json"));
                            il.add(new VarInsnNode(Opcodes.ASTORE, 1));

                            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            il.add(new JumpInsnNode(Opcodes.IFNONNULL, lblNotNull));

                            il.add(new FieldInsnNode(Opcodes.GETSTATIC, "kotlinx/serialization/json/Json", "Default", "Lkotlinx/serialization/json/Json$Default;"));
                            il.add(new InsnNode(Opcodes.ARETURN));

                            il.add(lblNotNull);
                            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            il.add(new InsnNode(Opcodes.ARETURN));

                            mn.instructions = il;
                            System.out.println("Patched ExtensionGenerated.c() with Json.Default fallback");
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
        System.out.println("Updated Flame Comics extension JAR successfully!");
    }
}
