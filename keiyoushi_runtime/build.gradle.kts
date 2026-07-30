import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

plugins {
    kotlin("jvm") version "2.0.0"
    kotlin("plugin.serialization") version "2.0.0"
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "eu.kanade.tachiyomi"
version = "2.0.0"

repositories {
    mavenCentral()
    maven { url = uri("https://jitpack.io") }
}

dependencies {
    implementation("io.javalin:javalin:6.1.6")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.17.1")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.1")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-brotli:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:4.12.0")

    implementation("org.jsoup:jsoup:1.17.2")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-rx2:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.7.1")

    implementation("org.ow2.asm:asm:9.6")
    implementation("org.ow2.asm:asm-commons:9.6")

    implementation("org.slf4j:slf4j-simple:2.0.13")

    implementation(kotlin("stdlib"))
    implementation(kotlin("reflect"))

    implementation("com.github.pxb1988.dex2jar:dex-tools:v2.4")
    implementation("com.github.pxb1988.dex2jar:dex-translator:v2.4")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        freeCompilerArgs.add("-Xskip-metadata-version-check")
        freeCompilerArgs.add("-Xallow-kotlin-package")
    }
}

tasks.jar {
    manifest {
        attributes["Main-Class"] = "eu.kanade.tachiyomi.runtime.MainKt"
    }
}

tasks.shadowJar {
    archiveBaseName.set("keiyoushi-runtime")
    archiveClassifier.set("")
    archiveVersion.set("")
    finalizedBy("patchOkHttp")
}

// Patch okhttp3 Request$Builder after shadow jar is created
tasks.register("patchOkHttp") {
    dependsOn(tasks.shadowJar)
    doLast {
        val jarFile = tasks.shadowJar.get().archiveFile.get().asFile
        val tempFile = File(jarFile.parent, "patched-${jarFile.name}")

        ZipInputStream(jarFile.inputStream()).use { zis ->
            ZipOutputStream(tempFile.outputStream()).use { zos ->
                var entry = zis.nextEntry
                while (entry != null) {
                    val bytes = zis.readBytes()
                    val outBytes = when (entry.name) {
                        "okhttp3/Request\$Builder.class" -> {
                            println("[PatchOkHttp] Patching okhttp3/Request\$Builder.class")
                            patchRequestBuilder(bytes)
                        }
                        "okhttp3/Request.class" -> {
                            println("[PatchOkHttp] Patching okhttp3/Request.class")
                            patchRequestBuilder(bytes) // same logic: remove Class.cast() calls
                        }
                        else -> bytes
                    }
                    zos.putNextEntry(ZipEntry(entry.name))
                    zos.write(outBytes)
                    zos.closeEntry()
                    entry = zis.nextEntry
                }
            }
        }
        jarFile.delete()
        tempFile.renameTo(jarFile)
        println("[PatchOkHttp] Done. Jar: ${jarFile.absolutePath}")
    }
}

fun patchRequestBuilder(bytes: ByteArray): ByteArray {
    val reader = org.objectweb.asm.ClassReader(bytes)
    val writer = object : org.objectweb.asm.ClassWriter(reader, org.objectweb.asm.ClassWriter.COMPUTE_MAXS) {
        override fun getCommonSuperClass(t1: String, t2: String) =
            try { super.getCommonSuperClass(t1, t2) } catch (_: Throwable) { "java/lang/Object" }
    }
    val className = reader.className // e.g. "okhttp3/Request" or "okhttp3/Request$Builder"
    val isGetter = !className.contains("Builder") // Request.tag(Class) is the getter

    val patcher = object : org.objectweb.asm.ClassVisitor(org.objectweb.asm.Opcodes.ASM9, writer) {
        override fun visitMethod(
            access: Int, name: String?, desc: String?,
            sig: String?, exceptions: Array<out String>?
        ): org.objectweb.asm.MethodVisitor {
            val mv = super.visitMethod(access, name, desc, sig, exceptions)
            if (name != "tag") return mv
            return object : org.objectweb.asm.MethodVisitor(org.objectweb.asm.Opcodes.ASM9, mv) {
                override fun visitMethodInsn(
                    opcode: Int, owner: String?, mname: String?,
                    mdesc: String?, isInterface: Boolean
                ) {
                    if (opcode == org.objectweb.asm.Opcodes.INVOKEVIRTUAL &&
                        owner == "java/lang/Class" && mname == "cast" &&
                        mdesc == "(Ljava/lang/Object;)Ljava/lang/Object;") {
                        if (isGetter) {
                            // Getter: stack = [type, mapValue]. Replace Class.cast(mapValue) with
                            // a safe instanceof check — if mapValue is NOT an instance of type,
                            // return null. This handles dex2jar bug where 'new x1' becomes 'new Object'.
                            // Stack in: [type, obj]  →  Stack out: [obj_or_null]
                            // Use: DUP2 → instanceof → SWAP → POP → conditional null
                            // Simpler: call our static helper safeTagCast(Class, Object):Object
                            super.visitMethodInsn(
                                org.objectweb.asm.Opcodes.INVOKESTATIC,
                                "eu/kanade/tachiyomi/runtime/loader/OkHttpTagPatch",
                                "safeTagGet",
                                "(Ljava/lang/Class;Ljava/lang/Object;)Ljava/lang/Object;",
                                false
                            )
                        } else {
                            // Setter: stack = [type, obj]. Replace Class.cast with SWAP+POP.
                            super.visitInsn(org.objectweb.asm.Opcodes.SWAP)
                            super.visitInsn(org.objectweb.asm.Opcodes.POP)
                        }
                        println("[PatchOkHttp]   Replaced Class.cast() in method $name$desc (isGetter=$isGetter)")
                        return
                    }
                    super.visitMethodInsn(opcode, owner, mname, mdesc, isInterface)
                }
            }
        }
    }
    reader.accept(patcher, org.objectweb.asm.ClassReader.EXPAND_FRAMES)
    return writer.toByteArray()
}

