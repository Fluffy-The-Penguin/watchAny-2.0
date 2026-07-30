package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class InjektPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_injekt.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("uy/kohesive/injekt/api/InjektScope.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("getInstance".equals(mn.name) && "(Ljava/lang/reflect/Type;)Ljava/lang/Object;".equals(mn.desc)) {
                            InsnList il = new InsnList();
                            LabelNode lblOriginal = new LabelNode();

                            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "uy/kohesive/injekt/api/FullTypeReferenceKt", "erasedType", "(Ljava/lang/reflect/Type;)Ljava/lang/Class;", false));
                            il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "getName", "()Ljava/lang/String;", false));
                            il.add(new LdcInsnNode("kotlinx.serialization.json.Json"));
                            il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/String", "equals", "(Ljava/lang/Object;)Z", false));
                            il.add(new JumpInsnNode(Opcodes.IFEQ, lblOriginal));

                            il.add(new FieldInsnNode(Opcodes.GETSTATIC, "runtime/JsonHelper", "LENIENT_JSON", "Lkotlinx/serialization/json/Json;"));
                            il.add(new InsnNode(Opcodes.ARETURN));

                            il.add(lblOriginal);
                            mn.instructions.insert(il);
                            System.out.println("Patched InjektScope.getInstance(Type) with direct JsonHelper.LENIENT_JSON return!");
                        }

                        if ("get".equals(mn.name) && "(Ljava/lang/Class;)Ljava/lang/Object;".equals(mn.desc)) {
                            InsnList il = new InsnList();
                            LabelNode lblOriginal = new LabelNode();

                            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "getName", "()Ljava/lang/String;", false));
                            il.add(new LdcInsnNode("kotlinx.serialization.json.Json"));
                            il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/String", "equals", "(Ljava/lang/Object;)Z", false));
                            il.add(new JumpInsnNode(Opcodes.IFEQ, lblOriginal));

                            il.add(new FieldInsnNode(Opcodes.GETSTATIC, "runtime/JsonHelper", "LENIENT_JSON", "Lkotlinx/serialization/json/Json;"));
                            il.add(new InsnNode(Opcodes.ARETURN));

                            il.add(lblOriginal);
                            mn.instructions.insert(il);
                            System.out.println("Patched InjektScope.get(Class) with direct JsonHelper.LENIENT_JSON return!");
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
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with direct JsonHelper.LENIENT_JSON!");
    }
}
