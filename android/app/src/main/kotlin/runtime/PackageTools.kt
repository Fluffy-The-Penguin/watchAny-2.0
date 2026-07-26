package runtime

import android.content.Context
import android.content.pm.Signature
import dalvik.system.DexClassLoader
import net.dongliu.apk.parser.ApkFile
import net.dongliu.apk.parser.ApkParsers
import org.w3c.dom.Element
import org.w3c.dom.Node
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.nameWithoutExtension

class ExtensionClassLoader(
    dexPath: String,
    librarySearchPath: String?,
    parent: ClassLoader
) : dalvik.system.PathClassLoader(dexPath, librarySearchPath, parent) {

    override fun loadClass(name: String, resolve: Boolean): Class<*> {
        if (name.startsWith("eu.kanade.tachiyomi.") ||
            name.startsWith("tachiyomi.") ||
            name.startsWith("uy.kohesive.injekt.") ||
            name.startsWith("okhttp3.") ||
            name.startsWith("rx.") ||
            name.startsWith("org.jsoup.") ||
            name.startsWith("kotlin.") ||
            name.startsWith("kotlinx.")
        ) {
            val parentClass = runCatching { parent.loadClass(name) }.getOrNull()
            if (parentClass != null) return parentClass
        }
        return super.loadClass(name, resolve)
    }
}

object PackageTools {
    const val EXTENSION_FEATURE = "tachiyomi.extension"
    const val METADATA_SOURCE_CLASS = "tachiyomi.extension.class"
    const val METADATA_SOURCE_FACTORY = "tachiyomi.extension.factory"
    const val METADATA_NSFW = "tachiyomi.extension.nsfw"
    const val LIB_VERSION_MIN = 1.0
    const val LIB_VERSION_MAX = 10.0


    private val dexLoaders = mutableMapOf<String, DexClassLoader>()


    fun getPackageMetadata(apkPath: Path): ApkMetadata {
        val apk = apkPath.toFile()
        val apkMeta = ApkParsers.getMetaInfo(apk)
        ApkFile(apk).use { parsed ->
            val manifestXml = parsed.manifestXml
            val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(manifestXml.byteInputStream())
            val metaData = linkedMapOf<String, String>()
            val features = mutableSetOf<String>()

            doc.getElementsByTagName("uses-feature").toNodeSequence().filterIsInstance<Element>().forEach { element ->
                element.attr("android:name")?.let(features::add)
            }
            val appTag = doc.getElementsByTagName("application").item(0)
            appTag?.childNodes?.toNodeSequence()?.filterIsInstance<Element>()?.filter { it.tagName == "meta-data" }?.forEach { element ->
                val name = element.attr("android:name") ?: return@forEach
                val value = element.attr("android:value") ?: element.attr("android:resource") ?: ""
                metaData[name] = value
            }

            val signatures = runCatching {
                parsed.apkSingers.flatMap { it.certificateMetas }.map { sha256(it.data) }
            }.getOrDefault(emptyList())

            return ApkMetadata(
                pkgName = apkMeta.packageName,
                versionName = apkMeta.versionName.orEmpty(),
                versionCode = apkMeta.versionCode?.toLong() ?: 0L,
                label = apkMeta.label.orEmpty(),
                iconPath = apkMeta.icon,
                features = features,
                metaData = metaData,
                sourceClasses = listOf(METADATA_SOURCE_CLASS, METADATA_SOURCE_FACTORY)
                    .flatMap { key -> metaData[key]?.split(';') ?: emptyList() }
                    .map { it.trim() }
                    .filter { it.isNotBlank() },
                nsfw = metaData[METADATA_NSFW] == "1",
                signatureHashes = signatures,
            )
        }
    }

    fun extractIcon(apkPath: Path, targetDir: Path): Path? {
        val icon = runCatching { ApkParsers.getMetaInfo(apkPath.toFile()).icon }.getOrNull()?.trim()?.trimStart('/')
        if (icon.isNullOrBlank()) return null
        val extension = icon.substringAfterLast('.', missingDelimiterValue = "png").lowercase()
        if (extension !in setOf("png", "webp", "jpg", "jpeg", "gif")) return null
        Files.createDirectories(targetDir)
        val safeName = apkPath.fileName.toString().removeSuffix(".apk").replace(Regex("[^A-Za-z0-9._-]"), "_")
        val target = targetDir.resolve("$safeName.$extension")
        ZipInputStream(Files.newInputStream(apkPath)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (!entry.isDirectory && entry.name.trimStart('/') == icon) {
                    Files.newOutputStream(target).use { zip.copyTo(it) }
                    return target
                }
                entry = zip.nextEntry
            }
        }
        return null
    }

    fun loadExtensionClass(context: Context, apkPath: Path, className: String, pkgName: String? = null): Any {
        val loader: ClassLoader = run {
            if (!pkgName.isNullOrBlank()) {
                val pathLoader = runCatching {
                    val appInfo = context.packageManager.getApplicationInfo(pkgName, 0)
                    eu.kanade.tachiyomi.util.system.ChildFirstPathClassLoader(appInfo.sourceDir, appInfo.nativeLibraryDir, PackageTools::class.java.classLoader)
                }.getOrNull()

                if (pathLoader != null) {
                    val testClass = runCatching { pathLoader.loadClass(className) }.getOrNull()
                    if (testClass != null) return@run pathLoader
                }
            }

            eu.kanade.tachiyomi.util.system.ChildFirstPathClassLoader(apkPath.toAbsolutePath().toString(), null, PackageTools::class.java.classLoader)
        }


        val clazz = loader.loadClass(className)

        return clazz.getDeclaredConstructor().newInstance()
    }




    private fun sha256(bytes: ByteArray): String {
        return MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

data class ApkMetadata(
    val pkgName: String,
    val versionName: String,
    val versionCode: Long,
    val label: String,
    val iconPath: String?,
    val features: Set<String>,
    val metaData: Map<String, String>,
    val sourceClasses: List<String>,
    val nsfw: Boolean,
    val signatureHashes: List<String>,
)

private fun org.w3c.dom.NodeList.toNodeSequence(): Sequence<Node> = sequence {
    for (index in 0 until length) yield(item(index))
}

private fun Element.attr(name: String): String? = attributes.getNamedItem(name)?.nodeValue
