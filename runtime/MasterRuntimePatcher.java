package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.jar.*;

public class MasterRuntimePatcher {

    public static void main(String[] args) {
        File jarFile = new File("assets/bin/keiyoushi-runtime.jar");
        File tmpFile = new File("assets/bin/keiyoushi-runtime.jar.tmp");

        if (!jarFile.exists()) {
            System.err.println("Runtime jar not found at " + jarFile.getAbsolutePath());
            return;
        }

        Set<String> addedEntries = new HashSet<>();

        try {
            try (JarFile jar = new JarFile(jarFile);
                 JarOutputStream jos = new JarOutputStream(new FileOutputStream(tmpFile))) {

                Enumeration<JarEntry> entries = jar.entries();
                while (entries.hasMoreElements()) {
                    JarEntry entry = entries.nextElement();
                    InputStream is = jar.getInputStream(entry);
                    byte[] bytes = is.readAllBytes();

                    if ((entry.getName().startsWith("runtime/") || entry.getName().startsWith("okhttp3/") || entry.getName().startsWith("eu/kanade/tachiyomi/network/")) && entry.getName().endsWith(".class")) {
                        File diskFile = new File(entry.getName());
                        if (diskFile.exists() && diskFile.isFile()) {
                            bytes = Files.readAllBytes(diskFile.toPath());
                            System.out.println("Replaced " + entry.getName() + " in jar from disk!");
                        }
                    } else if (entry.getName().endsWith("CatalogueSource.class")) {
                        bytes = patchCatalogueSource(bytes);
                    } else if (entry.getName().endsWith("HttpSource.class")) {
                        bytes = patchHttpSource(bytes);
                    } else if (entry.getName().endsWith("ChildFirstURLClassLoader.class")) {
                        bytes = patchClassLoader(bytes);
                    } else if (entry.getName().endsWith("LocalWebServer.class")) {
                        bytes = patchLocalWebServer(bytes);
                    } else if (entry.getName().endsWith("PackageTools.class")) {
                        bytes = patchPackageTools(bytes);
                    } else if (entry.getName().endsWith("ExtensionRuntime.class")) {
                        bytes = patchExtensionRuntime(bytes);
                    } else if (entry.getName().endsWith("InjektScope.class")) {
                        bytes = patchInjektScope(bytes);
                    } else if (entry.getName().endsWith("okhttp3/Request.class")) {
                        bytes = patchOkHttpTag(bytes);
                    } else if (entry.getName().endsWith("eu/kanade/tachiyomi/network/NetworkHelper.class")) {
                        bytes = patchNetworkHelper(bytes);
                    } else if (entry.getName().equals("eu/kanade/tachiyomi/source/model/SManga.class")) {
                        bytes = patchSMangaInterface(bytes);
                    } else if (entry.getName().equals("eu/kanade/tachiyomi/source/model/SMangaUpdate.class")) {
                        bytes = patchSMangaUpdateInterface(bytes);
                    } else if (entry.getName().equals("eu/kanade/tachiyomi/source/model/SMangaImpl.class")) {
                        bytes = patchSMangaImpl(bytes);
                    } else if (entry.getName().equals("eu/kanade/tachiyomi/source/model/SChapter.class")) {
                        bytes = patchSChapterInterface(bytes);
                    } else if (entry.getName().equals("eu/kanade/tachiyomi/source/model/SChapterImpl.class")) {
                        bytes = patchSChapterImpl(bytes);
                    }

                    JarEntry newEntry = new JarEntry(entry.getName());
                    jos.putNextEntry(newEntry);
                    jos.write(bytes);
                    jos.closeEntry();
                    addedEntries.add(entry.getName());
                }

                // Add runtime classes if missing
                addClassToJar(jos, addedEntries, "runtime/HttpSourceBridge.class");
                addClassToJar(jos, addedEntries, "runtime/HttpSourceBridge$1.class");
                addClassToJar(jos, addedEntries, "runtime/DynamicExtensionPatcher.class");
                addClassToJar(jos, addedEntries, "runtime/DummyInterceptors.class");
                addClassToJar(jos, addedEntries, "runtime/DummyInterceptors$UncaughtExceptionInterceptor.class");
                addClassToJar(jos, addedEntries, "runtime/DummyInterceptors$UserAgentInterceptor.class");
                addClassToJar(jos, addedEntries, "runtime/DummyInterceptors$CloudflareInterceptor.class");
                addClassToJar(jos, addedEntries, "runtime/DummyInterceptors$IgnoreGzipInterceptor.class");
                addClassToJar(jos, addedEntries, "runtime/DummyInterceptors$BrotliInterceptor.class");
                addClassToJar(jos, addedEntries, "okhttp3/CompressionInterceptor.class");
                addClassToJar(jos, addedEntries, "okhttp3/CompressionInterceptor$DecompressionAlgorithm.class");
                addClassToJar(jos, addedEntries, "eu/kanade/tachiyomi/source/online/HttpSourceBridgeHelper.class");
                addClassToJar(jos, addedEntries, "eu/kanade/tachiyomi/source/model/SMangaUpdate.class");

                // Scan disk directories for any extra class files (e.g. OkHttpExtensionsKt inner classes)
                addDirectoryClassesToJar(jos, addedEntries, new File("eu/kanade/tachiyomi/network"), "eu/kanade/tachiyomi/network");
                addDirectoryClassesToJar(jos, addedEntries, new File("eu/kanade/tachiyomi/source/online"), "eu/kanade/tachiyomi/source/online");
                addDirectoryClassesToJar(jos, addedEntries, new File("eu/kanade/tachiyomi/source/model"), "eu/kanade/tachiyomi/source/model");
                addDirectoryClassesToJar(jos, addedEntries, new File("runtime"), "runtime");
                addDirectoryClassesToJar(jos, addedEntries, new File("okhttp3"), "okhttp3");
            }

            Files.move(tmpFile.toPath(), jarFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            System.out.println("MasterRuntimePatcher successfully updated assets/bin/keiyoushi-runtime.jar!");

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static void addDirectoryClassesToJar(JarOutputStream jos, Set<String> addedEntries, File dir, String packagePath) {
        if (!dir.exists() || !dir.isDirectory()) return;
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                addDirectoryClassesToJar(jos, addedEntries, f, packagePath + "/" + f.getName());
            } else if (f.getName().endsWith(".class")) {
                String resourcePath = packagePath + "/" + f.getName();
                addClassToJar(jos, addedEntries, resourcePath);
            }
        }
    }

    private static void addClassToJar(JarOutputStream jos, Set<String> addedEntries, String classResourcePath) {
        if (addedEntries.contains(classResourcePath)) return;
        try {
            File f = new File(classResourcePath);
            if (f.exists()) {
                byte[] b = Files.readAllBytes(f.toPath());
                JarEntry entry = new JarEntry(classResourcePath);
                jos.putNextEntry(entry);
                jos.write(b);
                jos.closeEntry();
                addedEntries.add(classResourcePath);
                System.out.println("Added new entry to jar: " + classResourcePath);
            } else {
                System.out.println("File not found to add to jar: " + f.getAbsolutePath());
            }
        } catch (Exception e) {
            System.out.println("Failed adding " + classResourcePath + ": " + e.getMessage());
        }
    }

    private static byte[] patchNetworkHelper(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            if ("<init>".equals(mn.name)) {
                InsnList il = mn.instructions;
                for (int i = 0; i < il.size(); i++) {
                    AbstractInsnNode ain = il.get(i);
                    if (ain.getOpcode() == Opcodes.RETURN) {
                        InsnList patch = new InsnList();
                        patch.add(new VarInsnNode(Opcodes.ALOAD, 0));
                        patch.add(new VarInsnNode(Opcodes.ALOAD, 0));
                        patch.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "client", "Lokhttp3/OkHttpClient;"));
                        patch.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/DummyInterceptors", "addDummyInterceptors", "(Lokhttp3/OkHttpClient;)Lokhttp3/OkHttpClient;", false));
                        patch.add(new FieldInsnNode(Opcodes.PUTFIELD, cn.name, "client", "Lokhttp3/OkHttpClient;"));

                        patch.add(new VarInsnNode(Opcodes.ALOAD, 0));
                        patch.add(new VarInsnNode(Opcodes.ALOAD, 0));
                        patch.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "cloudflareClient", "Lokhttp3/OkHttpClient;"));
                        patch.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/DummyInterceptors", "addDummyInterceptors", "(Lokhttp3/OkHttpClient;)Lokhttp3/OkHttpClient;", false));
                        patch.add(new FieldInsnNode(Opcodes.PUTFIELD, cn.name, "cloudflareClient", "Lokhttp3/OkHttpClient;"));

                        il.insertBefore(ain, patch);
                        System.out.println("Injected DummyInterceptors into NetworkHelper.<init>!");
                        break;
                    }
                }
            } else if ("getClient".equals(mn.name) || "getCloudflareClient".equals(mn.name) || "getDefaultClient".equals(mn.name)) {
                InsnList il = new InsnList();
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "getCloudflareClient".equals(mn.name) ? "cloudflareClient" : "client", "Lokhttp3/OkHttpClient;"));
                il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/DummyInterceptors", "addDummyInterceptors", "(Lokhttp3/OkHttpClient;)Lokhttp3/OkHttpClient;", false));
                il.add(new InsnNode(Opcodes.ARETURN));
                mn.instructions = il;
                System.out.println("Patched NetworkHelper." + mn.name + " with DummyInterceptors!");
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchCatalogueSource(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            if ("fetchPopularManga".equals(mn.name) || "fetchSearchManga".equals(mn.name) || "fetchLatestUpdates".equals(mn.name)) {
                InsnList il = new InsnList();
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ILOAD, 1));
                if ("fetchSearchManga".equals(mn.name)) {
                    il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                    il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                    il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/HttpSourceBridge", mn.name, "(Leu/kanade/tachiyomi/source/CatalogueSource;ILjava/lang/String;Leu/kanade/tachiyomi/source/model/FilterList;)Lrx/Observable;", false));
                } else {
                    il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/HttpSourceBridge", mn.name, "(Leu/kanade/tachiyomi/source/CatalogueSource;I)Lrx/Observable;", false));
                }
                il.add(new InsnNode(Opcodes.ARETURN));

                mn.instructions = il;
                System.out.println("Patched CatalogueSource." + mn.name);
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchHttpSource(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            if ("fetchPopularManga".equals(mn.name) || "fetchSearchManga".equals(mn.name) || "fetchLatestUpdates".equals(mn.name)) {
                InsnList il = new InsnList();
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ILOAD, 1));
                if ("fetchSearchManga".equals(mn.name)) {
                    il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                    il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                    il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/HttpSourceBridge", mn.name, "(Leu/kanade/tachiyomi/source/CatalogueSource;ILjava/lang/String;Leu/kanade/tachiyomi/source/model/FilterList;)Lrx/Observable;", false));
                } else {
                    il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/HttpSourceBridge", mn.name, "(Leu/kanade/tachiyomi/source/CatalogueSource;I)Lrx/Observable;", false));
                }
                il.add(new InsnNode(Opcodes.ARETURN));

                mn.instructions = il;
                System.out.println("Patched HttpSource." + mn.name);
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchExtensionRuntime(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            InsnList list = mn.instructions;
            for (AbstractInsnNode ain : list) {
                if (ain instanceof LdcInsnNode) {
                    LdcInsnNode ldc = (LdcInsnNode) ain;
                    if (ldc.cst instanceof Double && ((Double) ldc.cst) == 1.5) {
                        ldc.cst = 10.0;
                        System.out.println("Patched LIB_VERSION_MAX double constant 1.5 to 10.0 in ExtensionRuntime." + mn.name);
                    }
                }
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchPackageTools(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (FieldNode fn : cn.fields) {
            if ("LIB_VERSION_MAX".equals(fn.name)) {
                fn.value = Double.valueOf(10.0);
                System.out.println("Patched LIB_VERSION_MAX field constant value to 10.0!");
            }
        }

        for (MethodNode mn : cn.methods) {
            if ("loadExtensionClass".equals(mn.name)) {
                boolean alreadyPatched = false;
                for (int i = 0; i < mn.instructions.size(); i++) {
                    AbstractInsnNode node = mn.instructions.get(i);
                    if (node instanceof MethodInsnNode && "patchPath".equals(((MethodInsnNode) node).name)) {
                        alreadyPatched = true;
                        break;
                    }
                }
                if (!alreadyPatched) {
                    InsnList patch = new InsnList();
                    patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                    patch.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/DynamicExtensionPatcher", "patchPath", "(Ljava/nio/file/Path;)Ljava/nio/file/Path;", false));
                    patch.add(new VarInsnNode(Opcodes.ASTORE, 1));
                    mn.instructions.insert(patch);
                    System.out.println("Injected patchPath into PackageTools.loadExtensionClass!");
                }
            }

            InsnList list = mn.instructions;
            for (AbstractInsnNode ain : list) {
                if (ain instanceof LdcInsnNode) {
                    LdcInsnNode ldc = (LdcInsnNode) ain;
                    if (ldc.cst instanceof Double && ((Double) ldc.cst) == 1.5) {
                        ldc.cst = 10.0;
                        System.out.println("Patched LIB_VERSION_MAX double constant 1.5 to 10.0 in Method " + mn.name);
                    }
                }
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchOkHttpTag(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            if ("tag".equals(mn.name) && "(Ljava/lang/Class;)Ljava/lang/Object;".equals(mn.desc)) {
                InsnList il = new InsnList();
                LabelNode lblNull = new LabelNode();

                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "okhttp3/Request", "tag", "()Ljava/lang/Object;", false));
                il.add(new VarInsnNode(Opcodes.ASTORE, 2));

                il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                il.add(new JumpInsnNode(Opcodes.IFNULL, lblNull));

                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "isInstance", "(Ljava/lang/Object;)Z", false));
                il.add(new JumpInsnNode(Opcodes.IFEQ, lblNull));

                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "cast", "(Ljava/lang/Object;)Ljava/lang/Object;", false));
                il.add(new InsnNode(Opcodes.ARETURN));

                il.add(lblNull);
                il.add(new InsnNode(Opcodes.ACONST_NULL));
                il.add(new InsnNode(Opcodes.ARETURN));

                mn.instructions = il;
                System.out.println("Patched okhttp3.Request.tag(Class)");
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchInjektScope(byte[] bytes) {
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
                System.out.println("Patched InjektScope.getInstance(Type)");
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
                System.out.println("Patched InjektScope.get(Class)");
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchSMangaInterface(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        boolean hasOriginalUrl = false;
        boolean hasMemo = false;
        for (MethodNode mn : cn.methods) {
            if ("getOriginalUrl".equals(mn.name)) {
                hasOriginalUrl = true;
            }
            if ("setMemo".equals(mn.name)) {
                hasMemo = true;
            }
        }

        if (!hasOriginalUrl) {
            MethodNode getOrig = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "getOriginalUrl", "()Ljava/lang/String;", null, null);
            MethodNode setOrig = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "setOriginalUrl", "(Ljava/lang/String;)V", null, null);
            cn.methods.add(getOrig);
            cn.methods.add(setOrig);
        }

        if (!hasMemo) {
            MethodNode getMemo = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "getMemo", "()Lkotlinx/serialization/json/JsonObject;", null, null);
            MethodNode setMemo = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "setMemo", "(Lkotlinx/serialization/json/JsonObject;)V", null, null);
            cn.methods.add(getMemo);
            cn.methods.add(setMemo);
        }

        boolean hasSMangaUpdate = false;
        for (String iface : cn.interfaces) {
            if ("eu/kanade/tachiyomi/source/model/SMangaUpdate".equals(iface)) {
                hasSMangaUpdate = true;
                break;
            }
        }
        if (!hasSMangaUpdate) {
            cn.interfaces.add("eu/kanade/tachiyomi/source/model/SMangaUpdate");
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchSMangaUpdateInterface(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        boolean hasGetManga = false;
        boolean hasGetChapters = false;
        for (MethodNode mn : cn.methods) {
            if ("getManga".equals(mn.name)) hasGetManga = true;
            if ("getChapters".equals(mn.name)) hasGetChapters = true;
        }

        if (!hasGetManga) {
            cn.methods.add(new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "getManga", "()Leu/kanade/tachiyomi/source/model/SManga;", null, null));
        }
        if (!hasGetChapters) {
            cn.methods.add(new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "getChapters", "()Ljava/util/List;", null, null));
        }

        System.out.println("Patched SMangaUpdate interface with getManga() and getChapters()!");

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchSMangaImpl(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            System.out.println("SMangaImpl method: " + mn.name + " desc=" + mn.desc);
            if (("getTitle".equals(mn.name) || "getArtist".equals(mn.name) || "getAuthor".equals(mn.name) || "getDescription".equals(mn.name) || "getGenre".equals(mn.name) || "getThumbnail_url".equals(mn.name)) && "()Ljava/lang/String;".equals(mn.desc)) {
                String fieldName = mn.name.substring(3, 4).toLowerCase() + mn.name.substring(4);
                if ("getThumbnail_url".equals(mn.name)) fieldName = "thumbnail_url";

                InsnList il = new InsnList();
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, fieldName, "Ljava/lang/String;"));
                LabelNode lblNotNull = new LabelNode();
                il.add(new InsnNode(Opcodes.DUP));
                il.add(new JumpInsnNode(Opcodes.IFNONNULL, lblNotNull));
                il.add(new InsnNode(Opcodes.POP));
                il.add(new LdcInsnNode(""));
                il.add(lblNotNull);
                il.add(new InsnNode(Opcodes.ARETURN));
                mn.instructions = il;
                System.out.println("Patched safe getter for " + mn.name + " in SMangaImpl");
            }
        }

        boolean hasField = false;
        boolean hasMemoField = false;
        for (FieldNode fn : cn.fields) {
            if ("originalUrl".equals(fn.name)) {
                hasField = true;
            }
            if ("memo".equals(fn.name)) {
                hasMemoField = true;
            }
        }

        if (!hasField) {
            cn.fields.add(new FieldNode(Opcodes.ACC_PRIVATE, "originalUrl", "Ljava/lang/String;", null, null));

            MethodNode getOrig = new MethodNode(Opcodes.ACC_PUBLIC, "getOriginalUrl", "()Ljava/lang/String;", null, null);
            InsnList il1 = new InsnList();
            il1.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il1.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "originalUrl", "Ljava/lang/String;"));
            il1.add(new InsnNode(Opcodes.ARETURN));
            getOrig.instructions = il1;
            cn.methods.add(getOrig);

            MethodNode setOrig = new MethodNode(Opcodes.ACC_PUBLIC, "setOriginalUrl", "(Ljava/lang/String;)V", null, null);
            InsnList il2 = new InsnList();
            il2.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il2.add(new VarInsnNode(Opcodes.ALOAD, 1));
            il2.add(new FieldInsnNode(Opcodes.PUTFIELD, cn.name, "originalUrl", "Ljava/lang/String;"));
            il2.add(new InsnNode(Opcodes.RETURN));
            setOrig.instructions = il2;
            cn.methods.add(setOrig);
        }

        if (!hasMemoField) {
            cn.fields.add(new FieldNode(Opcodes.ACC_PRIVATE, "memo", "Lkotlinx/serialization/json/JsonObject;", null, null));

            MethodNode getMemo = new MethodNode(Opcodes.ACC_PUBLIC, "getMemo", "()Lkotlinx/serialization/json/JsonObject;", null, null);
            InsnList il1 = new InsnList();
            il1.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il1.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "memo", "Lkotlinx/serialization/json/JsonObject;"));
            il1.add(new InsnNode(Opcodes.ARETURN));
            getMemo.instructions = il1;
            cn.methods.add(getMemo);

            MethodNode setMemo = new MethodNode(Opcodes.ACC_PUBLIC, "setMemo", "(Lkotlinx/serialization/json/JsonObject;)V", null, null);
            InsnList il2 = new InsnList();
            il2.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il2.add(new VarInsnNode(Opcodes.ALOAD, 1));
            il2.add(new FieldInsnNode(Opcodes.PUTFIELD, cn.name, "memo", "Lkotlinx/serialization/json/JsonObject;"));
            il2.add(new InsnNode(Opcodes.RETURN));
            setMemo.instructions = il2;
            cn.methods.add(setMemo);
        }

        // Inject chapters field & getManga() & getChapters() for SMangaUpdate
        boolean hasChaptersField = false;
        for (FieldNode fn : cn.fields) {
            if ("chapters".equals(fn.name)) {
                hasChaptersField = true;
                break;
            }
        }
        if (!hasChaptersField) {
            cn.fields.add(new FieldNode(Opcodes.ACC_PRIVATE, "chapters", "Ljava/util/List;", null, null));

            MethodNode getManga = new MethodNode(Opcodes.ACC_PUBLIC, "getManga", "()Leu/kanade/tachiyomi/source/model/SManga;", null, null);
            InsnList il1 = new InsnList();
            il1.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il1.add(new InsnNode(Opcodes.ARETURN));
            getManga.instructions = il1;
            cn.methods.add(getManga);

            MethodNode getChs = new MethodNode(Opcodes.ACC_PUBLIC, "getChapters", "()Ljava/util/List;", null, null);
            InsnList il2 = new InsnList();
            il2.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il2.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "chapters", "Ljava/util/List;"));
            il2.add(new InsnNode(Opcodes.ARETURN));
            getChs.instructions = il2;
            cn.methods.add(getChs);
        }

        // Inject constructor <init>(SManga, List)
        boolean hasMangaListInit = false;
        String descMangaListInit = "(Leu/kanade/tachiyomi/source/model/SManga;Ljava/util/List;)V";
        for (MethodNode mn : cn.methods) {
            if ("<init>".equals(mn.name) && descMangaListInit.equals(mn.desc)) {
                hasMangaListInit = true;
                break;
            }
        }
        if (!hasMangaListInit) {
            MethodNode init = new MethodNode(Opcodes.ACC_PUBLIC, "<init>", descMangaListInit, null, null);
            init.tryCatchBlocks = new java.util.ArrayList<>();
            InsnList il = new InsnList();
            il.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, cn.superName != null ? cn.superName : "java/lang/Object", "<init>", "()V", false));

            LabelNode lblNull = new LabelNode();
            il.add(new VarInsnNode(Opcodes.ALOAD, 1));
            il.add(new JumpInsnNode(Opcodes.IFNULL, lblNull));

            String[][] stringProps = {
                {"getUrl", "()Ljava/lang/String;", "setUrl", "(Ljava/lang/String;)V"},
                {"getTitle", "()Ljava/lang/String;", "setTitle", "(Ljava/lang/String;)V"},
                {"getArtist", "()Ljava/lang/String;", "setArtist", "(Ljava/lang/String;)V"},
                {"getAuthor", "()Ljava/lang/String;", "setAuthor", "(Ljava/lang/String;)V"},
                {"getDescription", "()Ljava/lang/String;", "setDescription", "(Ljava/lang/String;)V"},
                {"getGenre", "()Ljava/lang/String;", "setGenre", "(Ljava/lang/String;)V"},
                {"getThumbnail_url", "()Ljava/lang/String;", "setThumbnail_url", "(Ljava/lang/String;)V"}
            };

            for (String[] prop : stringProps) {
                LabelNode tStart = new LabelNode();
                LabelNode tEnd = new LabelNode();
                LabelNode tHandler = new LabelNode();
                LabelNode tNext = new LabelNode();

                init.tryCatchBlocks.add(new TryCatchBlockNode(tStart, tEnd, tHandler, "java/lang/Throwable"));

                il.add(tStart);
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, "eu/kanade/tachiyomi/source/model/SManga", prop[0], prop[1], true));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, cn.name, prop[2], prop[3], false));
                il.add(tEnd);
                il.add(new JumpInsnNode(Opcodes.GOTO, tNext));

                il.add(tHandler);
                il.add(new InsnNode(Opcodes.POP));

                il.add(tNext);
            }

            // Copy getStatus()
            {
                LabelNode tStart = new LabelNode();
                LabelNode tEnd = new LabelNode();
                LabelNode tHandler = new LabelNode();
                LabelNode tNext = new LabelNode();

                init.tryCatchBlocks.add(new TryCatchBlockNode(tStart, tEnd, tHandler, "java/lang/Throwable"));

                il.add(tStart);
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, "eu/kanade/tachiyomi/source/model/SManga", "getStatus", "()I", true));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, cn.name, "setStatus", "(I)V", false));
                il.add(tEnd);
                il.add(new JumpInsnNode(Opcodes.GOTO, tNext));

                il.add(tHandler);
                il.add(new InsnNode(Opcodes.POP));

                il.add(tNext);
            }

            // Copy getMemo()
            {
                LabelNode tStart = new LabelNode();
                LabelNode tEnd = new LabelNode();
                LabelNode tHandler = new LabelNode();
                LabelNode tNext = new LabelNode();

                init.tryCatchBlocks.add(new TryCatchBlockNode(tStart, tEnd, tHandler, "java/lang/Throwable"));

                il.add(tStart);
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, "eu/kanade/tachiyomi/source/model/SManga", "getMemo", "()Lkotlinx/serialization/json/JsonObject;", true));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, cn.name, "setMemo", "(Lkotlinx/serialization/json/JsonObject;)V", false));
                il.add(tEnd);
                il.add(new JumpInsnNode(Opcodes.GOTO, tNext));

                il.add(tHandler);
                il.add(new InsnNode(Opcodes.POP));

                il.add(tNext);
            }

            il.add(lblNull);
            il.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il.add(new VarInsnNode(Opcodes.ALOAD, 2));
            il.add(new FieldInsnNode(Opcodes.PUTFIELD, cn.name, "chapters", "Ljava/util/List;"));
            il.add(new InsnNode(Opcodes.RETURN));
            init.instructions = il;
            init.maxStack = 3;
            init.maxLocals = 3;
            cn.methods.add(init);
        }

        System.out.println("Patched SMangaImpl with originalUrl, memo, chapters fields, getManga()/getChapters(), and (SManga, List) constructor!");

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchSChapterInterface(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        boolean hasMemo = false;
        for (MethodNode mn : cn.methods) {
            if ("getMemo".equals(mn.name)) {
                hasMemo = true;
                break;
            }
        }

        if (!hasMemo) {
            MethodNode getMemo = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "getMemo", "()Lkotlinx/serialization/json/JsonObject;", null, null);
            MethodNode setMemo = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_ABSTRACT, "setMemo", "(Lkotlinx/serialization/json/JsonObject;)V", null, null);
            cn.methods.add(getMemo);
            cn.methods.add(setMemo);
        }

        System.out.println("Patched SChapter interface with getMemo/setMemo!");

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchSChapterImpl(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        boolean hasMemoField = false;
        for (FieldNode fn : cn.fields) {
            if ("memo".equals(fn.name)) {
                hasMemoField = true;
                break;
            }
        }

        if (!hasMemoField) {
            cn.fields.add(new FieldNode(Opcodes.ACC_PRIVATE, "memo", "Lkotlinx/serialization/json/JsonObject;", null, null));

            MethodNode getMemo = new MethodNode(Opcodes.ACC_PUBLIC, "getMemo", "()Lkotlinx/serialization/json/JsonObject;", null, null);
            InsnList il1 = new InsnList();
            il1.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il1.add(new FieldInsnNode(Opcodes.GETFIELD, cn.name, "memo", "Lkotlinx/serialization/json/JsonObject;"));
            il1.add(new InsnNode(Opcodes.ARETURN));
            getMemo.instructions = il1;
            cn.methods.add(getMemo);

            MethodNode setMemo = new MethodNode(Opcodes.ACC_PUBLIC, "setMemo", "(Lkotlinx/serialization/json/JsonObject;)V", null, null);
            InsnList il2 = new InsnList();
            il2.add(new VarInsnNode(Opcodes.ALOAD, 0));
            il2.add(new VarInsnNode(Opcodes.ALOAD, 1));
            il2.add(new FieldInsnNode(Opcodes.PUTFIELD, cn.name, "memo", "Lkotlinx/serialization/json/JsonObject;"));
            il2.add(new InsnNode(Opcodes.RETURN));
            setMemo.instructions = il2;
            cn.methods.add(setMemo);
        }

        System.out.println("Patched SChapterImpl with memo field!");

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchLocalWebServer(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            if ("errorJson".equals(mn.name)) {
                InsnList patch = new InsnList();
                patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/Throwable", "printStackTrace", "()V", false));
                mn.instructions.insert(patch);
                System.out.println("Injected printStackTrace into LocalWebServer.errorJson!");
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }

    private static byte[] patchClassLoader(byte[] bytes) {
        ClassReader cr = new ClassReader(bytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        for (MethodNode mn : cn.methods) {
            if ("loadClass".equals(mn.name) && "(Ljava/lang/String;Z)Ljava/lang/Class;".equals(mn.desc)) {
                InsnList il = new InsnList();

                LabelNode lblResolve = new LabelNode();
                LabelNode lblTryChild = new LabelNode();
                LabelNode lblTrySystem = new LabelNode();

                LabelNode lblCatchChild = new LabelNode();
                LabelNode lblCatchParent = new LabelNode();

                // 1. Check findLoadedClass(name)
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "runtime/ChildFirstURLClassLoader", "findLoadedClass", "(Ljava/lang/String;)Ljava/lang/Class;", false));
                il.add(new VarInsnNode(Opcodes.ASTORE, 3));

                il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                il.add(new JumpInsnNode(Opcodes.IFNONNULL, lblResolve));

                // 2. Check isParentFirst(name)
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "runtime/ChildFirstURLClassLoader", "isParentFirst", "(Ljava/lang/String;)Z", false));
                il.add(new JumpInsnNode(Opcodes.IFEQ, lblTryChild));

                // Try parent / system classloader first
                LabelNode lblParentTryStart = new LabelNode();
                LabelNode lblParentTryEnd = new LabelNode();
                mn.tryCatchBlocks.add(new TryCatchBlockNode(lblParentTryStart, lblParentTryEnd, lblCatchParent, "java/lang/ClassNotFoundException"));

                il.add(lblParentTryStart);
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "runtime/ChildFirstURLClassLoader", "getParent", "()Ljava/lang/ClassLoader;", false));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/ClassLoader", "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", false));
                il.add(new VarInsnNode(Opcodes.ASTORE, 3));
                il.add(lblParentTryEnd);

                il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                il.add(new JumpInsnNode(Opcodes.IFNONNULL, lblResolve));

                il.add(lblCatchParent);
                il.add(new InsnNode(Opcodes.POP));

                // 3. Try findClass(name) (Child first)
                il.add(lblTryChild);
                LabelNode lblChildTryStart = new LabelNode();
                LabelNode lblChildTryEnd = new LabelNode();
                mn.tryCatchBlocks.add(new TryCatchBlockNode(lblChildTryStart, lblChildTryEnd, lblCatchChild, "java/lang/ClassNotFoundException"));

                il.add(lblChildTryStart);
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "runtime/ChildFirstURLClassLoader", "findClass", "(Ljava/lang/String;)Ljava/lang/Class;", false));
                il.add(new VarInsnNode(Opcodes.ASTORE, 3));
                il.add(lblChildTryEnd);

                il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                il.add(new JumpInsnNode(Opcodes.IFNONNULL, lblResolve));

                il.add(lblCatchChild);
                il.add(new InsnNode(Opcodes.POP));

                // 4. Try systemClassLoader.loadClass(name) as fallback
                il.add(lblTrySystem);
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new FieldInsnNode(Opcodes.GETFIELD, "runtime/ChildFirstURLClassLoader", "systemClassLoader", "Ljava/lang/ClassLoader;"));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/ClassLoader", "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", false));
                il.add(new VarInsnNode(Opcodes.ASTORE, 3));

                // Resolve if requested
                il.add(lblResolve);
                LabelNode lblReturn = new LabelNode();
                il.add(new VarInsnNode(Opcodes.ILOAD, 2));
                il.add(new JumpInsnNode(Opcodes.IFEQ, lblReturn));
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "runtime/ChildFirstURLClassLoader", "resolveClass", "(Ljava/lang/Class;)V", false));

                il.add(lblReturn);
                il.add(new VarInsnNode(Opcodes.ALOAD, 3));
                il.add(new InsnNode(Opcodes.ARETURN));

                mn.instructions = il;
                System.out.println("Patched ChildFirstURLClassLoader.loadClass to correctly prioritize findClass when isParentFirst is false!");
            }

            if ("isParentFirst".equals(mn.name)) {
                InsnList il = new InsnList();
                LabelNode lblChildFirst = new LabelNode();
                LabelNode lblParentFirst = new LabelNode();

                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new LdcInsnNode("eu.kanade.tachiyomi.extension."));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/String", "startsWith", "(Ljava/lang/String;)Z", false));
                il.add(new JumpInsnNode(Opcodes.IFNE, lblChildFirst));

                String[] parentFirstPrefixes = new String[]{
                    "java.", "javax.", "jdk.", "sun.", "android.", "androidx.",
                    "eu.kanade.tachiyomi.", "tachiyomi.", "uy.kohesive.",
                    "kotlin.", "kotlinx.", "okhttp3.", "okio.", "org.jsoup."
                };

                for (String prefix : parentFirstPrefixes) {
                    il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                    il.add(new LdcInsnNode(prefix));
                    il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "java/lang/String", "startsWith", "(Ljava/lang/String;)Z", false));
                    il.add(new JumpInsnNode(Opcodes.IFNE, lblParentFirst));
                }

                // Default: CHILD FIRST (0)
                il.add(lblChildFirst);
                il.add(new InsnNode(Opcodes.ICONST_0));
                il.add(new InsnNode(Opcodes.IRETURN));

                // Parent first (1)
                il.add(lblParentFirst);
                il.add(new InsnNode(Opcodes.ICONST_1));
                il.add(new InsnNode(Opcodes.IRETURN));

                mn.instructions = il;
                System.out.println("Patched ChildFirstURLClassLoader.isParentFirst to default to CHILD FIRST!");
            }

            if ("<init>".equals(mn.name)) {
                InsnList patch = new InsnList();
                LabelNode lblEnd = new LabelNode();
                LabelNode lblLoop = new LabelNode();

                patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                patch.add(new JumpInsnNode(Opcodes.IFNULL, lblEnd));

                patch.add(new InsnNode(Opcodes.ICONST_0));
                patch.add(new VarInsnNode(Opcodes.ISTORE, 3));

                patch.add(lblLoop);
                patch.add(new VarInsnNode(Opcodes.ILOAD, 3));
                patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                patch.add(new InsnNode(Opcodes.ARRAYLENGTH));
                patch.add(new JumpInsnNode(Opcodes.IF_ICMPGE, lblEnd));

                patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                patch.add(new VarInsnNode(Opcodes.ILOAD, 3));
                patch.add(new VarInsnNode(Opcodes.ALOAD, 1));
                patch.add(new VarInsnNode(Opcodes.ILOAD, 3));
                patch.add(new InsnNode(Opcodes.AALOAD));
                patch.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "runtime/DynamicExtensionPatcher", "patchUrl", "(Ljava/net/URL;)Ljava/net/URL;", false));
                patch.add(new InsnNode(Opcodes.AASTORE));

                patch.add(new IincInsnNode(3, 1));
                patch.add(new JumpInsnNode(Opcodes.GOTO, lblLoop));

                patch.add(lblEnd);

                mn.instructions.insert(patch);
                System.out.println("Patched ChildFirstURLClassLoader constructor with Windows-safe DynamicExtensionPatcher.patchUrl!");
            }
        }

        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        cn.accept(cw);
        return cw.toByteArray();
    }
}
