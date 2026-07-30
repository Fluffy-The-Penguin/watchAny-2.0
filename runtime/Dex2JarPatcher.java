package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class Dex2JarPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tempFile = new File("temp_runtime_dex2jar.jar");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("com/googlecode/dex2jar/ir/ts/NewTransformer.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        if ("makeSureUsedBeforeConstructor".equals(mn.name)) {
                            InsnList list = mn.instructions;
                            for (AbstractInsnNode ain : list) {
                                if (ain.getOpcode() == Opcodes.INVOKEINTERFACE) {
                                    MethodInsnNode min = (MethodInsnNode) ain;
                                    if ("java/util/Iterator".equals(min.owner) && "remove".equals(min.name)) {
                                        list.set(ain, new InsnNode(Opcodes.POP));
                                        System.out.println("Patched NewTransformer.makeSureUsedBeforeConstructor to preserve object allocations!");
                                    }
                                }
                            }
                        }
                    }

                    ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
                    cn.accept(cw);
                    bytes = cw.toByteArray();
                }

                if ("com/googlecode/dex2jar/v3/V3.class".equals(entry.getName()) || "com/googlecode/dex2jar/v3/V3$1.class".equals(entry.getName())) {
                    // check V3 bytecode generator
                }

                JarEntry newEntry = new JarEntry(entry.getName());
                jos.putNextEntry(newEntry);
                jos.write(bytes);
                jos.closeEntry();
            }
        }

        Files.move(tempFile.toPath(), jarFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
        System.out.println("Updated assets/bin/keiyoushi-runtime.jar with Dex2JarPatcher successfully!");
    }
}
