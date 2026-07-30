package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class ClassLoaderPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_classloader.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("runtime/ChildFirstURLClassLoader.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("<init>".equals(mn.name)) {
                            InsnList patch = new InsnList();
                            LabelNode lblEnd = new LabelNode();
                            LabelNode lblLoop = new LabelNode();
                            LabelNode lblNext = new LabelNode();

                            patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            patch.add(new JumpInsnNode(Opcodes.IFNULL, lblEnd));

                            patch.add(new InsnNode(Opcodes.ICONST_0));
                            patch.add(new VarInsnNode(Opcodes.ISTORE, 3));

                            patch.add(lblLoop);
                            patch.add(new VarInsnNode(Opcodes.ILOAD, 3));
                            patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            patch.add(new InsnNode(Opcodes.ARRAYLENGTH));
                            patch.add(new JumpInsnNode(Opcodes.IF_ICMPGE, lblEnd));

                            LabelNode lblTryStart = new LabelNode();
                            LabelNode lblTryEnd = new LabelNode();
                            LabelNode lblCatch = new LabelNode();
                            mn.tryCatchBlocks.add(new TryCatchBlockNode(lblTryStart, lblTryEnd, lblCatch, "java/lang/Throwable"));

                            patch.add(lblTryStart);
                            patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                            patch.add(new VarInsnNode(Opcodes.ILOAD, 3));
                            patch.add(new InsnNode(Opcodes.AALOAD));
                            patch.add(new VarInsnNode(Opcodes.ASTORE, 4));

                            patch.add(new VarInsnNode(Opcodes.ALOAD, 4));
                            patch.add(new JumpInsnNode(Opcodes.IFNULL, lblNext));

                            patch.add(new TypeInsnNode(Opcodes.NEW, "java/io/File"));
                            patch.add(new InsnNode(Opcodes.DUP));
                            patch.add(new VarInsnNode(Opcodes.ALOAD, 4));
                            patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/net/URL", "toURI", "()Ljava/net/URI;", false));
                            patch.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "java/io/File", "<init>", "(Ljava/net/URI;)V", false));
                            patch.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/DynamicExtensionPatcher", "patchExtensionJar", "(Ljava/io/File;)V", false));

                            patch.add(lblTryEnd);
                            patch.add(new JumpInsnNode(Opcodes.GOTO, lblNext));

                            patch.add(lblCatch);
                            patch.add(new InsnNode(Opcodes.POP));

                            patch.add(lblNext);
                            patch.add(new IincInsnNode(3, 1));
                            patch.add(new JumpInsnNode(Opcodes.GOTO, lblLoop));

                            patch.add(lblEnd);

                            mn.instructions.insert(patch);
                            System.out.println("Patched ChildFirstURLClassLoader constructor with dynamic extension jar patcher!");
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
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with ClassLoaderPatcher successfully!");
    }
}
