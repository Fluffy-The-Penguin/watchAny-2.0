package runtime;

import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;

import java.io.*;
import java.net.URL;
import java.nio.file.*;
import java.util.*;
import java.util.jar.*;

public class DynamicExtensionPatcher {

    public static Path patchPath(Path origPath) {
        if (origPath == null) return null;
        File file = origPath.toFile();
        if (!file.exists()) return origPath;

        File patchedFile = getPatchedJarFile(file);
        return patchedFile.toPath();
    }

    public static File patchJar(File origJar) {
        if (origJar == null || !origJar.exists()) return origJar;
        return getPatchedJarFile(origJar);
    }

    public static URL patchUrl(URL origUrl) {
        if (origUrl == null) return null;
        try {
            String pathStr = origUrl.getPath();
            if (pathStr.startsWith("/") && pathStr.contains(":")) {
                pathStr = pathStr.substring(1);
            }
            File file = new File(pathStr);
            if (file.exists() && file.getName().endsWith(".jar") && !file.getName().endsWith(".patched.jar")) {
                File patched = getPatchedJarFile(file);
                return patched.toURI().toURL();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return origUrl;
    }

    private static synchronized File getPatchedJarFile(File origJar) {
        if (origJar.getName().contains(".patched.jar")) {
            return origJar;
        }

        File runtimeJar = new File("assets/bin/keiyoushi-runtime.jar");
        long runtimeTs = runtimeJar.exists() ? runtimeJar.lastModified() : 0L;
        File patchedJar = new File(origJar.getParentFile(), origJar.getName() + "." + origJar.lastModified() + "." + runtimeTs + ".v29.patched.jar");
        if (patchedJar.exists() && patchedJar.length() > 0) {
            return patchedJar;
        }

        File tmpJar = new File(origJar.getParentFile(), origJar.getName() + "." + System.currentTimeMillis() + ".tmp.jar");

        try (JarFile jar = new JarFile(origJar);
             JarOutputStream jos = new JarOutputStream(new FileOutputStream(tmpJar))) {

            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                InputStream is = jar.getInputStream(entry);
                byte[] bytes = is.readAllBytes();

                if (entry.getName().endsWith(".class") && !entry.getName().startsWith("META-INF")) {
                    try {
                        byte[] patched = patchClassBytes(jar, bytes);
                        if (patched != bytes) {
                            bytes = patched;
                        }
                    } catch (Exception e) {
                        System.err.println("[DynamicExtensionPatcher] PATCH ERROR on " + entry.getName() + ": " + e);
                    }
                }

                JarEntry newEntry = new JarEntry(entry.getName());
                jos.putNextEntry(newEntry);
                jos.write(bytes);
                jos.closeEntry();
            }
        } catch (Exception e) {
            tmpJar.delete();
            return origJar;
        }

        try {
            Files.move(tmpJar.toPath(), patchedJar.toPath(), StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            patchedJar = tmpJar;
        }

        System.out.println("[DynamicExtensionPatcher] Successfully created patched JAR: " + patchedJar.getName());
        return patchedJar;
    }

    public static byte[] patchClassBytes(JarFile jar, byte[] classBytes) {
        ClassReader cr = new ClassReader(classBytes);
        ClassNode cn = new ClassNode();
        cr.accept(cn, 0);

        if (cn.name.startsWith("okhttp3/") || cn.name.startsWith("kotlin/") || cn.name.startsWith("kotlinx/") || cn.name.startsWith("runtime/") || cn.name.startsWith("org/")) {
            return classBytes;
        }

        boolean changed = false;

        // ── 1a. Inject missing default constructor into classes without <init> ────────
        // R8 strips `<init>()V` constructors from stateless Companion/object classes.
        // Skip coroutine continuation classes (e.g. SuspendLambda, ContinuationImpl) so we don't invalidate their stackmap tables.
        {
            boolean hasInit = false;
            for (MethodNode mn : cn.methods) {
                if ("<init>".equals(mn.name)) {
                    hasInit = true;
                    break;
                }
            }
            boolean isCoroutine = cn.superName != null && (cn.superName.contains("Continuation") || cn.superName.contains("Lambda") || cn.superName.contains("Suspend"));
            if (!hasInit && !isCoroutine && (cn.access & Opcodes.ACC_INTERFACE) == 0) {
                MethodNode init = new MethodNode(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
                InsnList il = new InsnList();
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, cn.superName != null ? cn.superName : "java/lang/Object", "<init>", "()V", false));
                il.add(new InsnNode(Opcodes.RETURN));
                init.instructions = il;
                init.maxStack = 1;
                init.maxLocals = 1;
                cn.methods.add(init);
                changed = true;
                System.out.println("Injected missing <init>()V into class " + cn.name);
            }
        }

        // ── 1. Lambda superclass & instantiation patching ──────────────────────────
        // kotlin.jvm.internal.Lambda is Android-only and doesn't exist in standard JVM.
        // Replace superclass with java.lang.Object and fix any NEW kotlin/jvm/internal/Lambda instructions.
        if ("kotlin/jvm/internal/Lambda".equals(cn.superName)) {
            cn.superName = "java/lang/Object";
            changed = true;
            for (MethodNode mn : cn.methods) {
                if ("<init>".equals(mn.name)) {
                    InsnList insns = mn.instructions;
                    for (int i = 0; i < insns.size(); i++) {
                        AbstractInsnNode insn = insns.get(i);
                        if (insn.getOpcode() == Opcodes.INVOKESPECIAL) {
                            MethodInsnNode min = (MethodInsnNode) insn;
                            if ("kotlin/jvm/internal/Lambda".equals(min.owner) && "<init>".equals(min.name)) {
                                InsnList patch = new InsnList();
                                patch.add(new InsnNode(Opcodes.POP));
                                patch.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false));
                                insns.insertBefore(min, patch);
                                insns.remove(min);
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Replace any NEW kotlin/jvm/internal/Lambda (R8 optimizes lambda singletons in <clinit> to NEW Lambda)
        for (MethodNode mn : cn.methods) {
            InsnList insns = mn.instructions;
            for (int i = 0; i < insns.size(); i++) {
                AbstractInsnNode insn = insns.get(i);
                if (insn.getOpcode() == Opcodes.NEW) {
                    TypeInsnNode tin = (TypeInsnNode) insn;
                    if ("kotlin/jvm/internal/Lambda".equals(tin.desc)) {
                        String newType = "java/lang/Object";
                        // If followed by PUTSTATIC LfieldType;, use fieldType as target type
                        for (int k = i + 1; k < Math.min(i + 10, insns.size()); k++) {
                            AbstractInsnNode next = insns.get(k);
                            if (next.getOpcode() == Opcodes.PUTSTATIC) {
                                FieldInsnNode fin = (FieldInsnNode) next;
                                if (fin.desc.startsWith("L") && fin.desc.endsWith(";")) {
                                    newType = fin.desc.substring(1, fin.desc.length() - 1);
                                }
                                break;
                            }
                        }
                        tin.desc = newType;
                        changed = true;
                        System.out.println("Patched NEW Lambda -> NEW " + newType + " in " + cn.name + "." + mn.name);
                    }
                }
            }
        }

        // ── 1b. Inject getMangaDetails and getChapterList overrides for extensions using static suspend bridges ───
        // R8-compiled extensions implement details and chapters via `getMangaUpdate` and `fetchRelatedMangaList`:
        // `getMangaUpdate(SManga, List, z1, z2, Continuation)`: z1=true/z2=true returns SManga details & chapters.
        {
            String smangnDesc = "Leu/kanade/tachiyomi/source/model/SManga;";
            String contDesc = "Lkotlin/coroutines/Continuation;";
            String getMDDesc = "(" + smangnDesc + contDesc + ")Ljava/lang/Object;";
            String getMUDesc = "(" + smangnDesc + "Ljava/util/List;ZZ" + contDesc + ")Ljava/lang/Object;";

            boolean hasMangaUpdate = false;
            boolean hasStaticC = false;
            String staticCName = null;
            String staticCDesc = null;

            boolean hasMangaDetailsInstance = false;
            boolean hasChapterListInstance = false;

            for (MethodNode mn : cn.methods) {
                if ("getMangaUpdate".equals(mn.name) && getMUDesc.equals(mn.desc)) {
                    hasMangaUpdate = true;
                }
                if ((mn.access & Opcodes.ACC_STATIC) != 0 && mn.desc.startsWith("(L" + cn.name + ";" + smangnDesc) && !mn.desc.contains("Ljava/util/List;")) {
                    hasStaticC = true;
                    staticCName = mn.name;
                    staticCDesc = mn.desc;
                }
                if ("getMangaDetails".equals(mn.name) && getMDDesc.equals(mn.desc)) {
                    hasMangaDetailsInstance = true;
                }
                if ("getChapterList".equals(mn.name) && getMDDesc.equals(mn.desc)) {
                    hasChapterListInstance = true;
                }
            }

            if (hasMangaUpdate && !hasMangaDetailsInstance) {
                MethodNode getMD = new MethodNode(Opcodes.ACC_PUBLIC, "getMangaDetails", getMDDesc, null, null);
                InsnList il = getMD.instructions;
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new InsnNode(Opcodes.ACONST_NULL));
                il.add(new InsnNode(Opcodes.ICONST_1)); // z1 = true (details)
                il.add(new InsnNode(Opcodes.ICONST_0)); // z2 = false (no chapters lock)
                il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, cn.name, "getMangaUpdate", getMUDesc, false));

                LabelNode lblNotSuspended = new LabelNode();
                il.add(new InsnNode(Opcodes.DUP));
                il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, "kotlin/coroutines/intrinsics/IntrinsicsKt", "getCOROUTINE_SUSPENDED", "()Ljava/lang/Object;", false));
                il.add(new JumpInsnNode(Opcodes.IF_ACMPNE, lblNotSuspended));
                il.add(new InsnNode(Opcodes.ARETURN));

                il.add(lblNotSuspended);
                il.add(new TypeInsnNode(Opcodes.CHECKCAST, "eu/kanade/tachiyomi/source/model/SMangaImpl"));
                il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "eu/kanade/tachiyomi/source/model/SMangaImpl", "getManga", "()Leu/kanade/tachiyomi/source/model/SManga;", false));
                il.add(new InsnNode(Opcodes.ARETURN));
                getMD.maxStack = 6;
                getMD.maxLocals = 3;
                cn.methods.add(getMD);
                changed = true;
                System.out.println("Injected getMangaDetails -> getMangaUpdate(z1=true, z2=false).getManga() bridge in " + cn.name);
            }

            if (hasStaticC && !hasChapterListInstance) {
                MethodNode getCL = new MethodNode(Opcodes.ACC_PUBLIC, "getChapterList", getMDDesc, null, null);
                InsnList il = getCL.instructions;
                il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                il.add(new VarInsnNode(Opcodes.ALOAD, 2));
                il.add(new MethodInsnNode(Opcodes.INVOKESTATIC, cn.name, staticCName, staticCDesc, false));
                il.add(new InsnNode(Opcodes.ARETURN));
                getCL.maxStack = 3;
                getCL.maxLocals = 3;
                cn.methods.add(getCL);
                changed = true;
                System.out.println("Injected getChapterList -> static " + staticCName + "(this, manga, continuation) bridge in " + cn.name);
            }
        }

        // ── 1c. Replace getMangaUrl() body to handle null memo ────────────────────
        // Asura-style extensions build the web URL from a slug stored in SManga.memo.
        // When details are requested with just a URL (memo=null), getMangaUrl() NPEs.
        // Fix: REPLACE the entire method body with:
        //   if (memo == null) return getBaseUrl() + manga.getUrl();
        //   else { original body }
        // We replace the method completely using a wrapper that calls the renamed original.
        for (MethodNode mn : cn.methods) {
            if ("getMangaUrl".equals(mn.name) && "(Leu/kanade/tachiyomi/source/model/SManga;)Ljava/lang/String;".equals(mn.desc)) {
                boolean callsMemo = false;
                for (AbstractInsnNode ain : mn.instructions) {
                    if ((ain.getOpcode() == Opcodes.INVOKEINTERFACE || ain.getOpcode() == Opcodes.INVOKEVIRTUAL)
                            && "getMemo".equals(((MethodInsnNode)ain).name)) {
                        callsMemo = true;
                        break;
                    }
                }
                if (callsMemo) {
                    // Rename original to getMangaUrl$orig
                    mn.name = "getMangaUrl$orig";
                    // Create new getMangaUrl that null-checks memo then falls back to baseUrl+url
                    // Uses try/catch to catch any NPE from original body (safe fallback)
                    MethodNode wrapper = new MethodNode(
                        Opcodes.ACC_PUBLIC | Opcodes.ACC_FINAL,
                        "getMangaUrl",
                        "(Leu/kanade/tachiyomi/source/model/SManga;)Ljava/lang/String;",
                        null, null);
                    InsnList il = wrapper.instructions;
                    // try { return this.getMangaUrl$orig(manga); } catch (Throwable t) { return baseUrl+url; }
                    LabelNode tryStart = new LabelNode();
                    LabelNode tryEnd = new LabelNode();
                    LabelNode catchLabel = new LabelNode();
                    wrapper.tryCatchBlocks = new java.util.ArrayList<>();
                    wrapper.tryCatchBlocks.add(new org.objectweb.asm.tree.TryCatchBlockNode(tryStart, tryEnd, catchLabel, null));
                    il.add(tryStart);
                    il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                    il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                    il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, cn.name, "getMangaUrl$orig",
                        "(Leu/kanade/tachiyomi/source/model/SManga;)Ljava/lang/String;", false));
                    il.add(tryEnd);
                    il.add(new InsnNode(Opcodes.ARETURN));
                    // catch: return getBaseUrl() + manga.getUrl()
                    il.add(catchLabel);
                    il.add(new InsnNode(Opcodes.POP)); // pop exception
                    il.add(new VarInsnNode(Opcodes.ALOAD, 0));
                    il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, cn.name, "getBaseUrl", "()Ljava/lang/String;", false));
                    il.add(new VarInsnNode(Opcodes.ALOAD, 1));
                    il.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE,
                        "eu/kanade/tachiyomi/source/model/SManga", "getUrl", "()Ljava/lang/String;", true));
                    il.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL,
                        "java/lang/String", "concat", "(Ljava/lang/String;)Ljava/lang/String;", false));
                    il.add(new InsnNode(Opcodes.ARETURN));
                    wrapper.maxStack = 2;
                    wrapper.maxLocals = 2;
                    cn.methods.add(wrapper);
                    changed = true;
                    System.out.println("Replaced getMangaUrl() with null-memo fallback wrapper in " + cn.name);
                }
                break;
            }
        }

        // ── 2. Interceptor validation ATHROW neutralization ─────────────────────────

        // R8-obfuscated extensions check for specific OkHttp interceptors and throw if missing/present.
        // Neutralize these throws since our desktop OkHttp doesn't have those interceptors.
        for (MethodNode mn : cn.methods) {
            InsnList insns = mn.instructions;
            for (int i = 0; i < insns.size(); i++) {
                AbstractInsnNode insn = insns.get(i);
                if (insn.getOpcode() == Opcodes.LDC) {
                    LdcInsnNode ldc = (LdcInsnNode) insn;
                    if (ldc.cst instanceof String && (((String) ldc.cst).contains("must be present") || ((String) ldc.cst).contains("must not be present"))) {
                        for (int k = i + 1; k < Math.min(i + 10, insns.size()); k++) {
                            if (insns.get(k).getOpcode() == Opcodes.ATHROW) {
                                AbstractInsnNode athrowNode = insns.get(k);
                                InsnList patch = new InsnList();
                                patch.add(new InsnNode(Opcodes.POP));
                                String retType = mn.desc.substring(mn.desc.lastIndexOf(')') + 1);
                                if (retType.equals("Lokhttp3/OkHttpClient;")) {
                                    patch.add(new VarInsnNode(Opcodes.ALOAD, 0));
                                    patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "eu/kanade/tachiyomi/source/online/HttpSource", "getNetwork", "()Leu/kanade/tachiyomi/network/NetworkHelper;", false));
                                    patch.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL, "eu/kanade/tachiyomi/network/NetworkHelper", "getClient", "()Lokhttp3/OkHttpClient;", false));
                                    patch.add(new InsnNode(Opcodes.ARETURN));
                                } else if (retType.equals("V")) {
                                    patch.add(new InsnNode(Opcodes.RETURN));
                                } else if (retType.equals("I") || retType.equals("Z") || retType.equals("B") || retType.equals("C") || retType.equals("S")) {
                                    patch.add(new InsnNode(Opcodes.ICONST_0));
                                    patch.add(new InsnNode(Opcodes.IRETURN));
                                } else {
                                    patch.add(new InsnNode(Opcodes.ACONST_NULL));
                                    patch.add(new InsnNode(Opcodes.ARETURN));
                                }
                                insns.insertBefore(athrowNode, patch);
                                insns.remove(athrowNode);
                                changed = true;
                                System.out.println("Neutralized ATHROW for interceptor check in " + cn.name + "." + mn.name + ": " + ldc.cst);
                                break;
                            }
                        }
                    }
                }

                // ── 3. Compression algorithm GETSTATIC patches ───────────────────────────
                // Map Android Brotli/Gzip/Zstd to our CompressionInterceptor enum equivalents.
                if (insn.getOpcode() == Opcodes.GETSTATIC) {
                    FieldInsnNode fin = (FieldInsnNode) insn;
                    if ("okhttp3/brotli/Brotli".equals(fin.owner)) {
                        fin.owner = "okhttp3/CompressionInterceptor$DecompressionAlgorithm";
                        fin.name = "BROTLI";
                        fin.desc = "Lokhttp3/CompressionInterceptor$DecompressionAlgorithm;";
                        changed = true;
                    } else if ("okhttp3/Gzip".equals(fin.owner)) {
                        fin.owner = "okhttp3/CompressionInterceptor$DecompressionAlgorithm";
                        fin.name = "GZIP";
                        fin.desc = "Lokhttp3/CompressionInterceptor$DecompressionAlgorithm;";
                        changed = true;
                    } else if ("okhttp3/zstd/Zstd".equals(fin.owner)) {
                        fin.owner = "okhttp3/CompressionInterceptor$DecompressionAlgorithm";
                        fin.name = "ZSTD";
                        fin.desc = "Lokhttp3/CompressionInterceptor$DecompressionAlgorithm;";
                        changed = true;
                    }
                }


                // ── 5. Universal R8 NEW java/lang/Object fix ──────────────────────────────
                // R8 optimizes `new CustomClass()` to `new java/lang/Object()` when CustomClass
                // (e.g. Companion, Serializer, or Comparator) has no explicit constructor or fields.
                // Fix: Replace NEW java/lang/Object with NEW TargetType AND update the
                // corresponding INVOKESPECIAL java/lang/Object.<init>()V call to TargetType.<init>()V.
                if (insn.getOpcode() == Opcodes.NEW) {
                    TypeInsnNode tin = (TypeInsnNode) insn;
                    if ("java/lang/Object".equals(tin.desc)) {
                        for (int k = i + 1; k < Math.min(i + 15, insns.size()); k++) {
                            AbstractInsnNode next = insns.get(k);
                            String targetType = null;

                            if (next.getOpcode() == Opcodes.PUTSTATIC || next.getOpcode() == Opcodes.PUTFIELD) {
                                FieldInsnNode fin = (FieldInsnNode) next;
                                if (fin.desc.startsWith("L") && fin.desc.endsWith(";")) {
                                    String fieldType = fin.desc.substring(1, fin.desc.length() - 1);
                                    if ("java/util/Comparator".equals(fieldType)) {
                                        targetType = "runtime/DefaultComparator";
                                    } else if ("eu/kanade/tachiyomi/source/model/SMangaUpdate".equals(fieldType)) {
                                        targetType = "eu/kanade/tachiyomi/source/model/SMangaImpl";
                                    } else if (!fieldType.startsWith("java/") && !fieldType.startsWith("kotlin/") &&
                                               !fieldType.startsWith("kotlinx/") && !fieldType.startsWith("android/") &&
                                               !fieldType.startsWith("okhttp3/") && !fieldType.startsWith("org/")) {
                                        targetType = fieldType;
                                    }
                                }
                            } else if (next.getOpcode() == Opcodes.INVOKESTATIC || next.getOpcode() == Opcodes.INVOKEVIRTUAL || next.getOpcode() == Opcodes.INVOKEINTERFACE) {
                                MethodInsnNode min = (MethodInsnNode) next;
                                if (min.desc != null && min.desc.contains("Ljava/util/Comparator;")) {
                                    targetType = "runtime/DefaultComparator";
                                }
                            }

                            if (targetType != null) {
                                tin.desc = targetType;

                                // Also fix the INVOKESPECIAL java/lang/Object.<init>()V instruction between NEW and target
                                for (int j = i + 1; j < k; j++) {
                                    AbstractInsnNode subInsn = insns.get(j);
                                    if (subInsn.getOpcode() == Opcodes.INVOKESPECIAL) {
                                        MethodInsnNode min = (MethodInsnNode) subInsn;
                                        if ("java/lang/Object".equals(min.owner) && "<init>".equals(min.name)) {
                                            min.owner = targetType;
                                            break;
                                        }
                                    }
                                }

                                changed = true;
                                System.out.println("Fixed R8 init: NEW Object -> NEW " + targetType + " in " + cn.name + "." + mn.name);
                                break;
                            }

                            if (next.getOpcode() == Opcodes.RETURN || next.getOpcode() == Opcodes.ARETURN) {
                                break;
                            }
                        }
                    }
                }
                // ── 5b. Fix SMangaUpdate references to SMangaImpl ────────────────
                // The extension bytecode uses SMangaUpdate as a CLASS (new, checkcast, invokevirtual),
                // but our SMangaUpdate is an interface. We replace all references with SMangaImpl (concrete class).
                if (insn.getOpcode() == Opcodes.NEW) {
                    TypeInsnNode tin = (TypeInsnNode) insn;
                    if ("eu/kanade/tachiyomi/source/model/SMangaUpdate".equals(tin.desc)) {
                        tin.desc = "eu/kanade/tachiyomi/source/model/SMangaImpl";
                        changed = true;
                        System.out.println("Fixed NEW SMangaUpdate -> NEW SMangaImpl in " + cn.name + "." + mn.name);
                    }
                }
                if (insn.getOpcode() == Opcodes.CHECKCAST) {
                    TypeInsnNode tin = (TypeInsnNode) insn;
                    if ("eu/kanade/tachiyomi/source/model/SMangaUpdate".equals(tin.desc)) {
                        tin.desc = "eu/kanade/tachiyomi/source/model/SMangaImpl";
                        changed = true;
                        System.out.println("Fixed CHECKCAST SMangaUpdate -> SMangaImpl in " + cn.name + "." + mn.name);
                    }
                }
                if (insn.getOpcode() == Opcodes.INVOKESPECIAL) {
                    MethodInsnNode min = (MethodInsnNode) insn;
                    if ("eu/kanade/tachiyomi/source/model/SMangaUpdate".equals(min.owner)) {
                        min.owner = "eu/kanade/tachiyomi/source/model/SMangaImpl";
                        min.itf = false;
                        changed = true;
                    }
                }
                // INVOKEVIRTUAL on SMangaUpdate (interface) -> INVOKEVIRTUAL on SMangaImpl (concrete class)
                // This is the key fix: the JVM throws IncompatibleClassChangeError when INVOKEVIRTUAL
                // is used with an interface type. We change the owner to the concrete SMangaImpl.
                if (insn.getOpcode() == Opcodes.INVOKEVIRTUAL) {
                    MethodInsnNode min = (MethodInsnNode) insn;
                    if ("eu/kanade/tachiyomi/source/model/SMangaUpdate".equals(min.owner)) {
                        min.owner = "eu/kanade/tachiyomi/source/model/SMangaImpl";
                        min.itf = false;
                        changed = true;
                        System.out.println("Fixed INVOKEVIRTUAL SMangaUpdate." + min.name + " -> SMangaImpl in " + cn.name + "." + mn.name);
                    }
                }
                // Also patch INVOKEINTERFACE SMangaUpdate.* -> INVOKEINTERFACE SMangaUpdate.* is already correct
                // but if anything patches to INVOKEINTERFACE on wrong type, fix it
                if (insn.getOpcode() == Opcodes.INVOKEINTERFACE) {
                    MethodInsnNode min = (MethodInsnNode) insn;
                    // SMangaUpdate is our interface so INVOKEINTERFACE on it is fine, leave it
                }

                // ── 6. Asura Scans full URL patch ─────────────────────────────────────────
                // Popular item parser (`y0.a()`) sets SManga.url to `/series/` + `this.a` (which contains `/comics/slug-hash`).
                // Fix: In y0.a(), replace GETFIELD y0.b with GETFIELD y0.a AND replace LDC "/series/" with LDC "".
                // In ExtensionGenerated (b, c, e, getMangaUrl), replace LDC "/series/" with LDC "/comics/" so slug is extracted from /comics/ URL.
                if ("y0".equals(cn.name) && "a".equals(mn.name)) {
                    if (insn.getOpcode() == Opcodes.GETFIELD) {
                        FieldInsnNode fin = (FieldInsnNode) insn;
                        if ("b".equals(fin.name) && "y0".equals(fin.owner)) {
                            fin.name = "a";
                            changed = true;
                            System.out.println("Patched Asura Scans y0.a() to use full URL slug (field a)");
                        }
                    } else if (insn.getOpcode() == Opcodes.LDC) {
                        LdcInsnNode ldc = (LdcInsnNode) insn;
                        if ("/series/".equals(ldc.cst)) {
                            ldc.cst = "";
                            changed = true;
                            System.out.println("Patched Asura Scans y0.a() LDC /series/ to empty string");
                        }
                    }
                } else if (insn instanceof LdcInsnNode) {
                    LdcInsnNode ldc = (LdcInsnNode) insn;
                    if (ldc.cst instanceof String && ((String) ldc.cst).contains("/series/")) {
                        String str = (String) ldc.cst;
                        if (!str.startsWith("http://") && !str.startsWith("https://")) {
                            ldc.cst = str.replace("/series/", "/comics/");
                            changed = true;
                            System.out.println("Patched LDC /series/ -> /comics/ in " + cn.name + "." + mn.name + " (" + ldc.cst + ")");
                        }
                    }
                }


                // Some methods (not just Lambda subclass <init>) call Lambda.<init>(arity).
                // Replace with Object.<init>() since Lambda is Android-only.
                if (insn.getOpcode() == Opcodes.INVOKESPECIAL) {
                    MethodInsnNode min = (MethodInsnNode) insn;
                    if ("kotlin/jvm/internal/Lambda".equals(min.owner) && "<init>".equals(min.name)) {
                        InsnList patch = new InsnList();
                        patch.add(new InsnNode(Opcodes.POP)); // pop arity int
                        patch.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false));
                        insns.insertBefore(min, patch);
                        insns.remove(min);
                        changed = true;
                        System.out.println("Patched Lambda.<init> call in " + cn.name + "." + mn.name);
                    }
                }

                // ── 4. JsonObject/JsonElement Companion.serializer() inline ─────────────
                if (insn.getOpcode() == Opcodes.INVOKEVIRTUAL) {
                    MethodInsnNode min = (MethodInsnNode) insn;
                    if ("serializer".equals(min.name) && "()Lkotlinx/serialization/KSerializer;".equals(min.desc)) {
                        if ("kotlinx/serialization/json/JsonObject$Companion".equals(min.owner)) {
                            InsnList patch = new InsnList();
                            patch.add(new InsnNode(Opcodes.POP));
                            patch.add(new FieldInsnNode(Opcodes.GETSTATIC, "kotlinx/serialization/json/JsonObjectSerializer", "INSTANCE", "Lkotlinx/serialization/json/JsonObjectSerializer;"));
                            insns.insertBefore(min, patch);
                            insns.remove(min);
                            changed = true;
                            System.out.println("Inlined JsonObject$Companion.serializer to JsonObjectSerializer.INSTANCE");
                        } else if ("kotlinx/serialization/json/JsonElement$Companion".equals(min.owner)) {
                            InsnList patch = new InsnList();
                            patch.add(new InsnNode(Opcodes.POP));
                            patch.add(new FieldInsnNode(Opcodes.GETSTATIC, "kotlinx/serialization/json/JsonElementSerializer", "INSTANCE", "Lkotlinx/serialization/json/JsonElementSerializer;"));
                            insns.insertBefore(min, patch);
                            insns.remove(min);
                            changed = true;
                            System.out.println("Inlined JsonElement$Companion.serializer to JsonElementSerializer.INSTANCE");
                        }
                    }
                }

            } // end for each instruction
        } // end for each method

        if (changed) {
            ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES) {
                @Override
                protected String getCommonSuperClass(String type1, String type2) {
                    try {
                        return super.getCommonSuperClass(type1, type2);
                    } catch (Exception e) {
                        return "java/lang/Object";
                    }
                }
            };
            cn.accept(cw);
            return cw.toByteArray();
        }

        return classBytes;
    }


    private static Map<String, Boolean> serializerOrCompanionCache = new HashMap<>();

    private static JarEntry findJarEntry(JarFile jar, String owner) {
        if (owner == null) return null;
        Enumeration<JarEntry> entries = jar.entries();
        while (entries.hasMoreElements()) {
            JarEntry e = entries.nextElement();
            String fullName = e.getName();
            if (fullName.endsWith(".class")) {
                String className = fullName.substring(0, fullName.length() - 6);
                if (className.equals(owner)) {
                    return e;
                }
            }
        }
        return null;
    }

    private static boolean isSerializerOrCompanionClass(JarFile jar, String className) {
        if (className == null) return false;
        if (serializerOrCompanionCache.containsKey(className)) {
            return serializerOrCompanionCache.get(className);
        }

        JarEntry entry = findJarEntry(jar, className);
        if (entry == null) {
            serializerOrCompanionCache.put(className, false);
            return false;
        }

        try (InputStream is = jar.getInputStream(entry)) {
            ClassReader cr = new ClassReader(is);
            ClassNode cn = new ClassNode();
            cr.accept(cn, 0);

            boolean result = cn.name.endsWith("$Companion") ||
                             cn.name.contains("$Companion$");

            if (!result && cn.interfaces != null) {
                for (String iface : cn.interfaces) {
                    if (iface.contains("GeneratedSerializer") || iface.contains("KSerializer")) {
                        // Only match actual serializer implementations, not just any Serializable-like interface
                        result = true;
                        break;
                    }
                }
            }
            // NOTE: Do NOT treat kotlin/jvm/internal/Lambda subclasses as serializers —
            // they are coroutine lambdas/functions, not GeneratedSerializer implementations.
            // Instantiating them with NEW breaks the GeneratedSerializer interface check.

            serializerOrCompanionCache.put(className, result);
            return result;
        } catch (Exception e) {
            serializerOrCompanionCache.put(className, false);
            return false;
        }
    }

    private static FieldInsnNode findSerializerStaticField(JarFile jar, String companionClassName) {
        JarEntry entry = findJarEntry(jar, companionClassName);
        if (entry == null) return null;

        try (InputStream is = jar.getInputStream(entry)) {
            ClassReader cr = new ClassReader(is);
            ClassNode cn = new ClassNode();
            cr.accept(cn, 0);

            for (MethodNode mn : cn.methods) {
                if ("serializer".equals(mn.name)) {
                    for (AbstractInsnNode insn : mn.instructions) {
                        if (insn.getOpcode() == Opcodes.GETSTATIC) {
                            return (FieldInsnNode) insn;
                        }
                    }
                }
            }
        } catch (Exception e) {
            // ignore
        }
        return null;
    }

    private static String findParameterizedSerializerClass(JarFile jar, String companionClassName) {
        JarEntry entry = findJarEntry(jar, companionClassName);
        if (entry == null) return null;

        try (InputStream is = jar.getInputStream(entry)) {
            ClassReader cr = new ClassReader(is);
            ClassNode cn = new ClassNode();
            cr.accept(cn, 0);

            for (MethodNode mn : cn.methods) {
                if ("serializer".equals(mn.name)) {
                    for (AbstractInsnNode insn : mn.instructions) {
                        if (insn.getOpcode() == Opcodes.NEW) {
                            return ((TypeInsnNode) insn).desc;
                        }
                    }
                }
            }
        } catch (Exception e) {
            // ignore
        }
        return null;
    }
}
