package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class OkHttpTagPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_tag.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("okhttp3/Request.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("tag".equals(mn.name) && "(Ljava/lang/Class;)Ljava/lang/Object;".equals(mn.desc)) {
                            // Replace method body with safe type check
                            mn.instructions.clear();
                            mn.tryCatchBlocks.clear();
                            mn.localVariables.clear();

                            InsnList il = new InsnList();
                            // aload_0 (this)
                            // getfield tags
                            il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                            il.add(new FieldInsnNode(Opcodes.GETFIELD, "okhttp3/Request", "tags", "Ljava/util/Map;"));
                            // aload_1 (Class type)
                            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            // invokeinterface Map.get(Object) -> Object
                            il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, "java/util/Map", "get", "(Ljava/lang/Object;)Ljava/lang/Object;", true));
                            il.add(new VarInsnNode(Opcodes.ASTORE, 2));

                            // if (tag2 == null) try Map.get(Object.class)
                            LabelNode lblNotNull = new LabelNode();
                            il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                            il.add(new JumpInsnNode(Opcodes.IFNONNULL, lblNotNull));

                            il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                            il.add(new FieldInsnNode(Opcodes.GETFIELD, "okhttp3/Request", "tags", "Ljava/util/Map;"));
                            il.add(new LdcInsnNode(Type.getType("Ljava/lang/Object;")));
                            il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, "java/util/Map", "get", "(Ljava/lang/Object;)Ljava/lang/Object;", true));
                            il.add(new VarInsnNode(Opcodes.ASTORE, 2));

                            il.add(lblNotNull);

                            // if (tag2 != null && type.isInstance(tag2)) return type.cast(tag2);
                            LabelNode lblReturnNull = new LabelNode();
                            il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                            il.add(new JumpInsnNode(Opcodes.IFNULL, lblReturnNull));

                            il.add(new VarInsnNode(Opcodes.ALOAD, 1)); // type
                            il.add(new VarInsnNode(Opcodes.ALOAD, 2)); // tag2
                            il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "isInstance", "(Ljava/lang/Object;)Z", false));
                            il.add(new JumpInsnNode(Opcodes.IFEQ, lblReturnNull));

                            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                            il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "cast", "(Ljava/lang/Object;)Ljava/lang/Object;", false));
                            il.add(new InsnNode(Opcodes.ARETURN));

                            il.add(lblReturnNull);
                            il.add(new InsnNode(Opcodes.ACONST_NULL));
                            il.add(new InsnNode(Opcodes.ARETURN));

                            mn.instructions = il;
                            System.out.println("Patched okhttp3.Request.tag(Class) with safe type check");
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
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with safe OkHttp tag method!");
    }
}
