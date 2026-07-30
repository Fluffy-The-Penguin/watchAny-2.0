package eu.kanade.tachiyomi.runtime.loader

import com.googlecode.dex2jar.tools.Dex2jarCmd
import org.objectweb.asm.*
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object ApkLoader {

    private val cacheDir = File(System.getProperty("user.home"), ".keiyoushi/cache").apply { mkdirs() }

    fun loadApk(apkFile: File): File {
        val cacheKey = "${apkFile.nameWithoutExtension}_${apkFile.lastModified()}_${apkFile.length()}"
        val cachedJar = File(cacheDir, "$cacheKey.jar")
        if (cachedJar.exists() && cachedJar.length() > 0) {
            println("[ApkLoader] Loading cached JAR for ${apkFile.name} (${cachedJar.length()} bytes)")
            return cachedJar
        }

        println("[ApkLoader] Converting ${apkFile.name} with dex2jar...")
        val tempJar = File.createTempFile("ext_dex2jar_", ".jar")
        tempJar.deleteOnExit()

        try {
            val cmd = Dex2jarCmd()
            val args = arrayOf("-f", "-o", tempJar.absolutePath, apkFile.absolutePath)
            cmd.doMain(*args)
        } catch (e: Exception) {
            println("[ApkLoader] Dex2jar failed for ${apkFile.name}: ${e.message}")
            throw e
        }

        val tempProcessedJar = File.createTempFile("ext_processed_", ".jar")
        tempProcessedJar.deleteOnExit()

        ZipInputStream(tempJar.inputStream()).use { zis ->
            ZipOutputStream(FileOutputStream(tempProcessedJar)).use { zos ->
                var entry: ZipEntry? = zis.nextEntry
                while (entry != null) {
                    val entryName = entry.name
                    if (entryName.endsWith(".class")) {
                        val bytes = zis.readBytes()
                        val modifiedBytes = processClassBytes(bytes)
                        zos.putNextEntry(ZipEntry(entryName))
                        zos.write(modifiedBytes)
                        zos.closeEntry()
                    } else {
                        zos.putNextEntry(ZipEntry(entryName))
                        zis.copyTo(zos)
                        zos.closeEntry()
                    }
                    entry = zis.nextEntry
                }
            }
        }

        try {
            tempProcessedJar.copyTo(cachedJar, overwrite = true)
            println("[ApkLoader] Saved processed JAR to cache: ${cachedJar.name}")
            return cachedJar
        } catch (e: Exception) {
            println("[ApkLoader] Warning: Failed to save to cache: $e")
            return tempProcessedJar
        }
    }

    private fun processClassBytes(bytes: ByteArray): ByteArray {
        val reader = ClassReader(bytes)

        // First attempt: COMPUTE_FRAMES with EXPAND_FRAMES
        val writer = object : ClassWriter(reader, COMPUTE_FRAMES) {
            override fun getCommonSuperClass(type1: String, type2: String): String =
                try { super.getCommonSuperClass(type1, type2) } catch (_: Throwable) { "java/lang/Object" }
        }
        return try {
            reader.accept(buildVisitor(writer), ClassReader.EXPAND_FRAMES)
            writer.toByteArray()
        } catch (e: Throwable) {
            val className = try { reader.className } catch (_: Throwable) { "?" }
            // Second attempt: apply rewrites with COMPUTE_MAXS without touching class version header
            try {
                val writer2 = object : ClassWriter(reader, COMPUTE_MAXS) {
                    override fun getCommonSuperClass(type1: String, type2: String): String =
                        try { super.getCommonSuperClass(type1, type2) } catch (_: Throwable) { "java/lang/Object" }
                }
                reader.accept(buildVisitor(writer2), ClassReader.EXPAND_FRAMES)
                writer2.toByteArray()
            } catch (e2: Throwable) {
                bytes
            }
        }
    }

    /** Builds the rewriting ClassVisitor against the given writer. Extracted so we can reuse for fallback. */
    private fun buildVisitor(writer: ClassWriter): ClassVisitor {
        return object : ClassVisitor(Opcodes.ASM9, writer) {
            private var currentClassName: String = ""

            override fun visit(
                version: Int, access: Int, name: String,
                signature: String?, superName: String?, interfaces: Array<out String>?
            ) {
                currentClassName = name
                super.visit(version, access, name, signature, superName, interfaces)
            }

            override fun visitMethod(
                access: Int, name: String?, descriptor: String?,
                signature: String?, exceptions: Array<out String>?
            ): MethodVisitor {
                val currentMethodName = name ?: ""
                val mv = super.visitMethod(access, name, descriptor, signature, exceptions)
                val isStaticInit = name == "<clinit>"
                return object : MethodVisitor(Opcodes.ASM9, mv) {
                    override fun visitTypeInsn(opcode: Int, type: String) {
                        // In static initializers (<clinit>), dex2jar wrongly emits
                        // `NEW kotlin/jvm/internal/Lambda` when it should emit `NEW <currentClass>`.
                        // This happens when inner Lambda subclasses are initialized as statics.
                        if (opcode == Opcodes.NEW && type == "kotlin/jvm/internal/Lambda" && isStaticInit && currentClassName.isNotEmpty()) {
                            println("[ApkLoader] Rewrote NEW kotlin/jvm/internal/Lambda -> NEW $currentClassName (in <clinit>)")
                            super.visitTypeInsn(opcode, currentClassName)
                            return
                        }
                        super.visitTypeInsn(opcode, type)
                    }

                    override fun visitMethodInsn(
                        opcode: Int, owner: String?, name: String?,
                        descriptor: String?, isInterface: Boolean
                    ) {
                        if (opcode == Opcodes.INVOKESTATIC && owner == "kotlinx/serialization/json/okio/OkioStreamsKt" && name == "decodeFromBufferedSource") {
                            super.visitMethodInsn(
                                Opcodes.INVOKESTATIC,
                                "eu/kanade/tachiyomi/network/OkHttpExtensionsKt",
                                "decodeFromBufferedSource",
                                "(Lkotlinx/serialization/json/Json;Lkotlinx/serialization/DeserializationStrategy;Lokio/BufferedSource;)Ljava/lang/Object;",
                                false
                            )
                            println("[ApkLoader] Rewrote OkioStreamsKt.decodeFromBufferedSource -> OkHttpExtensionsKt.decodeFromBufferedSource")
                            return
                        }
                        if (name == "sortedWith" && (owner?.contains("CollectionsKt") == true)) {
                            super.visitMethodInsn(
                                Opcodes.INVOKESTATIC,
                                "eu/kanade/tachiyomi/network/OkHttpExtensionsKt",
                                "safeSortedWith",
                                "(Ljava/lang/Iterable;Ljava/lang/Object;)Ljava/util/List;",
                                false
                            )
                            println("[ApkLoader] Rewrote CollectionsKt.sortedWith -> OkHttpExtensionsKt.safeSortedWith")
                            return
                        }
                        if (name == "decodeFromString" && (owner == "kotlinx/serialization/json/Json" || owner == "kotlinx/serialization/StringFormat")) {
                            super.visitMethodInsn(
                                Opcodes.INVOKESTATIC,
                                "eu/kanade/tachiyomi/network/OkHttpExtensionsKt",
                                "decodeFromString",
                                "(Lkotlinx/serialization/json/Json;Lkotlinx/serialization/DeserializationStrategy;Ljava/lang/String;)Ljava/lang/Object;",
                                false
                            )
                            return
                        }
                        if (name == "serializer" && opcode == Opcodes.INVOKEVIRTUAL) {
                            val paramCount = Type.getArgumentTypes(descriptor).size
                            if (paramCount == 0) {
                                super.visitLdcInsn(owner ?: "")
                                super.visitMethodInsn(
                                    Opcodes.INVOKESTATIC,
                                    "eu/kanade/tachiyomi/network/OkHttpExtensionsKt",
                                    "safeGetSerializer0",
                                    "(Ljava/lang/Object;Ljava/lang/String;)Lkotlinx/serialization/KSerializer;",
                                    false
                                )
                                println("[ApkLoader] Rewrote $owner.serializer() -> OkHttpExtensionsKt.safeGetSerializer0")
                                return
                            } else if (paramCount == 1) {
                                super.visitLdcInsn(owner ?: "")
                                super.visitMethodInsn(
                                    Opcodes.INVOKESTATIC,
                                    "eu/kanade/tachiyomi/network/OkHttpExtensionsKt",
                                    "safeGetSerializer1",
                                    "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)Lkotlinx/serialization/KSerializer;",
                                    false
                                )
                                println("[ApkLoader] Rewrote $owner.serializer(param) -> OkHttpExtensionsKt.safeGetSerializer1")
                                return
                            }
                        }

                        if (opcode == Opcodes.INVOKEVIRTUAL && owner == "java/lang/Object" && name == "getClass" && descriptor == "()Ljava/lang/Class;") {
                            val lbl = org.objectweb.asm.Label()
                            super.visitInsn(Opcodes.DUP)
                            super.visitJumpInsn(Opcodes.IFNONNULL, lbl)
                            super.visitInsn(Opcodes.POP)
                            super.visitLdcInsn(org.objectweb.asm.Type.getType("Ljava/lang/Object;"))
                            super.visitLabel(lbl)
                            super.visitMethodInsn(opcode, owner, name, descriptor, isInterface)
                            return
                        }
                        super.visitMethodInsn(opcode, owner, name, descriptor, isInterface)
                    }

                }
            }
        }
    }
}
