package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class LogPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_log.jar");

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
                        if ("<init>".equals(mn.name) && mn.desc.startsWith("(Ljava/lang/String;")) {
                            InsnList patch = new InsnList();
                            patch.add(new FieldInsnNode(Opcodes.GETSTATIC, "java/lang/System", "err", "Ljava/io/PrintStream;"));
                            patch.add(new TypeInsnNode(Opcodes.NEW, "java/lang/StringBuilder"));
                            patch.add(new InsnNode(Opcodes.DUP));
                            patch.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "java/lang/StringBuilder", "<init>", "()V", false));
                            patch.add(new LdcInsnNode("[SourceLoadError] "));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", false));
                            patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", false));
                            patch.add(new LdcInsnNode(" - "));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", false));
                            patch.add(new VarInsnNode(Opcodes.ALOAD, 2));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", false));
                            patch.add(new LdcInsnNode(": "));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", false));
                            patch.add(new VarInsnNode(Opcodes.ALOAD, 3));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", false));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;", false));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false));

                            mn.instructions.insert(patch);
                            System.out.println("Injected safe logging into SourceLoadError constructor!");
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
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with LogPatcher successfully!");
    }
}
