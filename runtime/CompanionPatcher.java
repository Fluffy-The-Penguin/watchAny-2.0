package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class CompanionPatcher {
    public static void patchJarFile(File jarFile) {
        if (!jarFile.exists() || !jarFile.getName().endsWith(".jar")) return;
        File tempFile = new File(jarFile.getAbsolutePath() + ".tmp");
        boolean modified = false;

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if (entry.getName().endsWith(".class") && !entry.getName().startsWith("META-INF")) {
                    try {
                        byte[] patched = patchClassBytes(bytes);
                        if (patched != bytes) {
                            bytes = patched;
                            modified = true;
                        }
                    } catch (Exception e) {
                        // ignore unparseable class
                    }
                }

                JarEntry newEntry = new JarEntry(entry.getName());
                jos.putNextEntry(newEntry);
                jos.write(bytes);
                jos.closeEntry();
            }
        } catch (Exception e) {
            e.printStackTrace();
            tempFile.delete();
            return;
        }

        if (modified) {
            try {
                Files.move(tempFile.toPath(), jarFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                System.out.println("Successfully patched companion allocations in: " + jarFile.getName());
            } catch (Exception e) {
                e.printStackTrace();
            }
        } else {
            tempFile.delete();
        }
    }

    public static byte[] patchClassBytes(byte[] classBytes) {
        ClassReader cr = new ClassReader(classBytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        // Skip standard framework classes
        if (cn.name.startsWith("okhttp3/") || cn.name.startsWith("kotlin/") || cn.name.startsWith("runtime/") || cn.name.startsWith("org/")) {
            return classBytes;
        }

        boolean changed = false;

        for (MethodNode mn : cn.methods) {
            InsnList insns = mn.instructions;
            for (int i = 0; i < insns.size(); i++) {
                AbstractInsnNode insn = insns.get(i);
                if (insn.getOpcode() == Opcodes.NEW) {
                    TypeInsnNode newInsn = (TypeInsnNode) insn;
                    if ("java/lang/Object".equals(newInsn.desc)) {
                        for (int j = i + 1; j < Math.min(i + 15, insns.size()); j++) {
                            AbstractInsnNode next = insns.get(j);
                            
                            // Check if used in PUTSTATIC / PUTFIELD
                            if (next.getOpcode() == Opcodes.PUTSTATIC || next.getOpcode() == Opcodes.PUTFIELD) {
                                FieldInsnNode fin = (FieldInsnNode) next;
                                String fieldType = fin.desc;
                                if (fieldType.startsWith("L") && fieldType.endsWith(";") && !fieldType.equals("Ljava/lang/Object;")) {
                                    String targetClass = fieldType.substring(1, fieldType.length() - 1);
                                    newInsn.desc = targetClass;

                                    for (int k = i + 1; k < j; k++) {
                                        AbstractInsnNode call = insns.get(k);
                                        if (call.getOpcode() == Opcodes.INVOKESPECIAL) {
                                            MethodInsnNode min = (MethodInsnNode) call;
                                            if ("java/lang/Object".equals(min.owner) && "<init>".equals(min.name)) {
                                                min.owner = targetClass;
                                            }
                                        }
                                    }
                                    changed = true;
                                    System.out.println("Patched Object allocation -> " + targetClass + " in " + cn.name + "." + mn.name);
                                    break;
                                }
                            }

                            // Check if passed to sortedWith / Comparator
                            if (next.getOpcode() == Opcodes.INVOKESTATIC) {
                                MethodInsnNode min = (MethodInsnNode) next;
                                if ("sortedWith".equals(min.name) || min.desc.contains("Ljava/util/Comparator;")) {
                                    newInsn.desc = "runtime/DefaultComparator";
                                    for (int k = i + 1; k < j; k++) {
                                        AbstractInsnNode call = insns.get(k);
                                        if (call.getOpcode() == Opcodes.INVOKESPECIAL) {
                                            MethodInsnNode min2 = (MethodInsnNode) call;
                                            if ("java/lang/Object".equals(min2.owner) && "<init>".equals(min2.name)) {
                                                min2.owner = "runtime/DefaultComparator";
                                            }
                                        }
                                    }
                                    changed = true;
                                    System.out.println("Patched Object allocation -> DefaultComparator in " + cn.name + "." + mn.name);
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        if (changed) {
            ClassWriter cw = new ClassWriter(0);
            cn.accept(cw);
            return cw.toByteArray();
        }

        return classBytes;
    }

    public static void main(String[] args) {
        if (args.length > 0) {
            File file = new File(args[0]);
            if (file.isDirectory()) {
                File[] files = file.listFiles();
                if (files != null) {
                    for (File f : files) {
                        if (f.getName().endsWith(".jar")) patchJarFile(f);
                    }
                }
            } else {
                patchJarFile(file);
            }
        }
    }
}
