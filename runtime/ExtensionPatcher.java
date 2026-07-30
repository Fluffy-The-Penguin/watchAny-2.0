package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class ExtensionPatcher {
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
                System.out.println("Successfully patched zero-constructor classes in: " + jarFile.getName());
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

        // Don't patch interfaces or abstract classes
        if ((cn.access & Opcodes.ACC_INTERFACE) != 0 || (cn.access & Opcodes.ACC_ABSTRACT) != 0) {
            return classBytes;
        }

        boolean hasInit = false;
        for (MethodNode mn : cn.methods) {
            if ("<init>".equals(mn.name)) {
                hasInit = true;
                break;
            }
        }

        if (!hasInit) {
            MethodVisitor mv = cn.visitMethod(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
            mv.visitCode();
            mv.visitVarInsn(Opcodes.ALOAD, 0);
            String superName = cn.superName != null ? cn.superName : "java/lang/Object";
            mv.visitMethodInsn(Opcodes.INVOKESPECIAL, superName, "<init>", "()V", false);
            mv.visitInsn(Opcodes.RETURN);
            mv.visitMaxs(1, 1);
            mv.visitEnd();

            ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
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
