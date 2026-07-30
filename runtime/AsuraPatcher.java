package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.io.*;
import java.nio.file.*;
import java.util.Enumeration;
import java.util.jar.*;

public class AsuraPatcher {
    public static void main(String[] args) throws Exception {
        File jarFile = new File("C:\\Users\\aryan\\AppData\\Roaming\\com.example\\watch_any\\keiyoushi\\jar\\tachiyomi-en.asurascans-v1.6.66.jar");
        File tempFile = new File(jarFile.getAbsolutePath() + ".tmp");

        try (JarFile jar = new JarFile(jarFile);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tempFile))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if ("eu/kanade/tachiyomi/extension/en/asurascans/ExtensionGenerated.class".equals(entry.getName())) {
                    ClassReader cr = new ClassReader(bytes);
                    ClassNode cn = new ClassNode();
                    cr.accept(cn, 0);

                    for (MethodNode mn : cn.methods) {
                        InsnList list = mn.instructions;
                        for (AbstractInsnNode ain : list) {
                            if (ain.getOpcode() == Opcodes.GETSTATIC) {
                                FieldInsnNode fin = (FieldInsnNode) ain;
                                if ("okhttp3/brotli/Brotli".equals(fin.owner)) {
                                    fin.owner = "okhttp3/CompressionInterceptor$DecompressionAlgorithm";
                                    fin.name = "BROTLI";
                                    fin.desc = "Lokhttp3/CompressionInterceptor$DecompressionAlgorithm;";
                                    System.out.println("Patched Brotli.INSTANCE -> DecompressionAlgorithm.BROTLI in Asura Scans!");
                                } else if ("okhttp3/Gzip".equals(fin.owner)) {
                                    fin.owner = "okhttp3/CompressionInterceptor$DecompressionAlgorithm";
                                    fin.name = "GZIP";
                                    fin.desc = "Lokhttp3/CompressionInterceptor$DecompressionAlgorithm;";
                                    System.out.println("Patched Gzip.INSTANCE -> DecompressionAlgorithm.GZIP in Asura Scans!");
                                } else if ("okhttp3/zstd/Zstd".equals(fin.owner)) {
                                    fin.owner = "okhttp3/CompressionInterceptor$DecompressionAlgorithm";
                                    fin.name = "ZSTD";
                                    fin.desc = "Lokhttp3/CompressionInterceptor$DecompressionAlgorithm;";
                                    System.out.println("Patched Zstd.INSTANCE -> DecompressionAlgorithm.ZSTD in Asura Scans!");
                                }
                            }
                            if (ain.getOpcode() == Opcodes.LDC) {
                                LdcInsnNode ldc = (LdcInsnNode) ain;
                                if ("BrotliInterceptor must not be present in default client".equals(ldc.cst)) {
                                    AbstractInsnNode prev = ldc.getPrevious();
                                    while (prev != null) {
                                        if (prev instanceof JumpInsnNode) {
                                            JumpInsnNode jin = (JumpInsnNode) prev;
                                            jin.setOpcode(Opcodes.GOTO);
                                            System.out.println("Patched Asura Scans BrotliInterceptor validation check to bypass exception!");
                                            break;
                                        }
                                        prev = prev.getPrevious();
                                    }
                                }
                            }
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
        System.out.println("Updated Asura Scans extension JAR successfully with AsuraPatcher!");
    }
}
