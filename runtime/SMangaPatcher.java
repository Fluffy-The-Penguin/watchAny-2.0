package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class SMangaPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_smanga.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("eu/kanade/tachiyomi/source/model/SManga.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    // Add default JsonObject getMemo()
                    MethodNode getMemo = new MethodNode(
                        Opcodes.ACC_PUBLIC,
                        "getMemo",
                        "()Lkotlinx/serialization/json/JsonObject;",
                        null,
                        null
                    );
                    InsnList il1 = new InsnList();
                    il1.add(new InsnNode(Opcodes.ACONST_NULL));
                    il1.add(new InsnNode(Opcodes.ARETURN));
                    getMemo.instructions = il1;
                    cn.methods.add(getMemo);

                    // Add default void setMemo(JsonObject)
                    MethodNode setMemo = new MethodNode(
                        Opcodes.ACC_PUBLIC,
                        "setMemo",
                        "(Lkotlinx/serialization/json/JsonObject;)V",
                        null,
                        null
                    );
                    InsnList il2 = new InsnList();
                    il2.add(new InsnNode(Opcodes.RETURN));
                    setMemo.instructions = il2;
                    cn.methods.add(setMemo);

                    ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
                    cn.accept(cw);
                    bytes = cw.toByteArray();
                    System.out.println("Added getMemo and setMemo to SManga interface!");
                }

                if ("eu/kanade/tachiyomi/source/model/SMangaImpl.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    // Add field memo
                    cn.fields.add(new FieldNode(
                        Opcodes.ACC_PRIVATE,
                        "memo",
                        "Lkotlinx/serialization/json/JsonObject;",
                        null,
                        null
                    ));

                    // Add getMemo()
                    MethodNode getMemo = new MethodNode(
                        Opcodes.ACC_PUBLIC,
                        "getMemo",
                        "()Lkotlinx/serialization/json/JsonObject;",
                        null,
                        null
                    );
                    InsnList il1 = new InsnList();
                    il1.add(new VarInsnNode(Opcodes.ALOAD, 0));
                    il1.add(new FieldInsnNode(Opcodes.GETFIELD, "eu/kanade/tachiyomi/source/model/SMangaImpl", "memo", "Lkotlinx/serialization/json/JsonObject;"));
                    il1.add(new InsnNode(Opcodes.ARETURN));
                    getMemo.instructions = il1;
                    cn.methods.add(getMemo);

                    // Add setMemo(JsonObject)
                    MethodNode setMemo = new MethodNode(
                        Opcodes.ACC_PUBLIC,
                        "setMemo",
                        "(Lkotlinx/serialization/json/JsonObject;)V",
                        null,
                        null
                    );
                    InsnList il2 = new InsnList();
                    il2.add(new VarInsnNode(Opcodes.ALOAD, 0));
                    il2.add(new VarInsnNode(Opcodes.ALOAD, 1));
                    il2.add(new FieldInsnNode(Opcodes.PUTFIELD, "eu/kanade/tachiyomi/source/model/SMangaImpl", "memo", "Lkotlinx/serialization/json/JsonObject;"));
                    il2.add(new InsnNode(Opcodes.RETURN));
                    setMemo.instructions = il2;
                    cn.methods.add(setMemo);

                    ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
                    cn.accept(cw);
                    bytes = cw.toByteArray();
                    System.out.println("Added getMemo and setMemo implementation to SMangaImpl!");
                }

                JarEntry newEntry = new JarEntry(entry.getName());
                jos.putNextEntry(newEntry);
                jos.write(bytes);
                jos.closeEntry();
            }
        }

        Files.move(tempFile.toPath(), jarFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with SMangaPatcher successfully!");
    }
}
