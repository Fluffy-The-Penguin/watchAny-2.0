package eu.kanade.tachiyomi.runtime.loader

import java.io.File
import java.net.URL
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

object ExtensionManager {
    val extensionDir = File(System.getProperty("user.home"), ".keiyoushi/extensions").apply { mkdirs() }
    private val repositories = mutableListOf(
        "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json",
        "https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.min.json"
    )

    fun addRepository(url: String) {
        if (!repositories.contains(url)) {
            repositories.add(0, url)
        }
    }

    fun getRepositories(): List<Map<String, String>> {
        return repositories.map { mapOf("indexUrl" to it) }
    }

    fun loadAllInstalledExtensions() {
        val files = extensionDir.listFiles { _, name -> name.endsWith(".jar") || name.endsWith(".apk") } ?: return
        val uniqueFiles = files.groupBy { file ->
            // Group by base name without version suffix, e.g. "eu.kanade.tachiyomi.extension.en.asurascans"
            file.nameWithoutExtension.substringBefore("-v")
        }.map { (_, fileGroup) ->
            fileGroup.find { it.name.endsWith(".apk") } ?: fileGroup.first()
        }

        uniqueFiles.forEach { file ->
            // pkgName is the filename without extension and version suffix
            val pkgName = file.nameWithoutExtension.substringBefore("-v")
            val jarFile = ApkLoader.loadApk(file)
            ExtensionLoader.loadJar(jarFile, pkgName)
        }
    }

    fun getInstalledExtensions(): List<Map<String, Any>> {
        return ExtensionLoader.getAllSources().map { source ->
            mapOf(
                "name" to source.name,
                "pkg" to "eu.kanade.tachiyomi.extension.${source.lang}.${source.name.lowercase().replace(" ", "")}",
                "version" to "1.4.0",
                "lang" to source.lang,
                "nsfw" to 0
            )
        }
    }

    private fun fetchUrl(urlStr: String): ByteArray {
        val conn = (java.net.URI(urlStr).toURL().openConnection() as java.net.HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            connectTimeout = 15000
            readTimeout = 30000
            instanceFollowRedirects = true
        }
        return conn.inputStream.use { it.readBytes() }
    }

    fun getAvailableExtensions(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        for (repoUrl in repositories) {
            try {
                val jsonStr = fetchUrl(repoUrl).toString(Charsets.UTF_8)
                val jsonArr = Json.parseToJsonElement(jsonStr).jsonArray
                for (elem in jsonArr) {
                    val obj = elem.jsonObject
                    val name = obj["name"]?.jsonPrimitive?.content ?: continue
                    val pkg = obj["pkg"]?.jsonPrimitive?.content ?: continue
                    val version = obj["version"]?.jsonPrimitive?.content ?: "1.0.0"
                    val lang = obj["lang"]?.jsonPrimitive?.content ?: "en"
                    // Keiyoushi index.min.json uses "apk" as the APK filename field
                    val apkName = obj["apk"]?.jsonPrimitive?.content
                        ?: obj["apkName"]?.jsonPrimitive?.content
                        ?: continue

                    result.add(
                        mapOf(
                            "name" to name,
                            "pkg" to pkg,
                            "version" to version,
                            "lang" to lang,
                            "nsfw" to 0,
                            "apkName" to apkName,
                            "repoUrl" to repoUrl
                        )
                    )
                }
                if (result.isNotEmpty()) break
            } catch (e: Exception) {
                println("[ExtensionManager] Error fetching repo $repoUrl: $e")
            }
        }
        return result
    }

    fun installExtension(pkgName: String): Boolean {
        try {
            val available = getAvailableExtensions()
            val target = available.find { it["pkg"] == pkgName } ?: return false
            val apkName = target["apkName"] as? String ?: return false
            val repoUrl = target["repoUrl"] as? String ?: return false

            val downloadUrl = repoUrl.substringBeforeLast('/') + "/apk/" + apkName
            val destFile = File(extensionDir, "$pkgName.apk")

            println("[ExtensionManager] Downloading $downloadUrl to ${destFile.name}...")
            val apkBytes = fetchUrl(downloadUrl)
            destFile.writeBytes(apkBytes)

            val jarFile = ApkLoader.loadApk(destFile)
            val source = ExtensionLoader.loadJar(jarFile, pkgName)
            if (source != null) {
                println("[ExtensionManager] Installed and loaded source: ${source.name}")
                return true
            } else {
                println("[ExtensionManager] Failed to load source from ${destFile.name}")
                return false
            }
        } catch (e: Exception) {
            println("[ExtensionManager] Failed to install $pkgName: $e")
            return false
        }
    }

    fun uninstallExtension(pkgName: String): Boolean {
        val apkFile = File(extensionDir, "$pkgName.apk")
        val jarFile = File(extensionDir, "$pkgName.jar")
        var deleted = false
        if (apkFile.exists()) deleted = apkFile.delete() || deleted
        if (jarFile.exists()) deleted = jarFile.delete() || deleted
        // Remove from in-memory source registry
        ExtensionLoader.removeSource(pkgName)
        return true
    }
}
