package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class LazyPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_lazy.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("kotlin/SynchronizedLazyImpl.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("getValue".equals(mn.name)) {
                            InsnList list = mn.instructions;
                            AbstractInsnNode target = null;
                            for (AbstractInsnNode ain : list) {
                                if (ain.getOpcode() == Opcodes.INVOKEINTERFACE) {
                                    MethodInsnNode min = (MethodInsnNode) ain;
                                    if ("kotlin/jvm/functions/Function0".equals(min.owner) && "invoke".equals(min.name)) {
                                        target = ain;
                                        break;
                                    }
                                }
                            }

                            if (target != null) {
                                InsnList patch = new InsnList();
                                LabelNode lblOk = new LabelNode();

                                patch.add(new InsnNode(Opcodes.DUP));
                                patch.add(new JumpInsnNode(Opcodes.IFNONNULL, lblOk));
                                patch.add(new InsnNode(Opcodes.POP));
                                patch.add(new FieldInsnNode(Opcodes.GETSTATIC, "runtime/JsonHelper", "LENIENT_JSON", "Lkotlinx/serialization/json/Json;"));
                                patch.add(lblOk);

                                list.insert(target, patch);
                                System.out.println("Patched SynchronizedLazyImpl.getValue() with null-to-LENIENT_JSON fallback!");
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
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with SynchronizedLazyImpl JsonHelper patch!");
    }
}
