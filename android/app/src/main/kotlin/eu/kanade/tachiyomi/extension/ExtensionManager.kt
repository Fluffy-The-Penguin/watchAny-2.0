package eu.kanade.tachiyomi.extension

import android.content.Context
import eu.kanade.tachiyomi.extension.api.ExtensionApi
import eu.kanade.tachiyomi.extension.model.Extension
import eu.kanade.tachiyomi.extension.model.LoadResult
import eu.kanade.tachiyomi.extension.util.ExtensionLoader
import eu.kanade.tachiyomi.source.AndroidSourceManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File

/**
 * Mihon & Komikku Extension Manager.
 * Orchestrates extension discovery, installation, uninstallation, and source registration.
 */
class ExtensionManager(
    private val context: Context,
    val sourceManager: AndroidSourceManager = AndroidSourceManager(context)
) {

    private val scope = CoroutineScope(Dispatchers.IO)
    private val api = ExtensionApi()
    private val client = OkHttpClient()

    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    private val _installedExtensions = MutableStateFlow<List<Extension.Installed>>(emptyList())
    val installedExtensions: StateFlow<List<Extension.Installed>> = _installedExtensions.asStateFlow()

    private val _availableExtensions = MutableStateFlow<List<Extension.Available>>(emptyList())
    val availableExtensions: StateFlow<List<Extension.Available>> = _availableExtensions.asStateFlow()

    init {
        initExtensions()
    }

    fun initExtensions() {
        scope.launch {
            val results = ExtensionLoader.loadExtensions(context)
            val installed = results.filterIsInstance<LoadResult.Success>().map { it.extension }
            _installedExtensions.value = installed

            // Register sources into sourceManager
            val allSources = installed.flatMap { it.sources }
            sourceManager.registerSources(allSources)

            _isInitialized.value = true
        }
    }

    suspend fun findAvailableExtensions(indexUrl: String = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"): List<Extension.Available> {
        val available = try {
            api.fetchExtensions(indexUrl)
        } catch (e: Throwable) {
            android.util.Log.e("watchAny-ExtensionManager", "Error fetching available extensions from $indexUrl: ${e.message}", e)
            emptyList()
        }
        _availableExtensions.value = available
        return available
    }

    suspend fun installExtension(apkUrl: String): Extension.Installed? {
        val tempFile = File(context.cacheDir, "temp_ext_${System.currentTimeMillis()}.apk")
        try {
            val request = Request.Builder().url(apkUrl).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("HTTP ${response.code} downloading $apkUrl")
                tempFile.outputStream().use { out -> response.body.byteStream().copyTo(out) }
            }

            val targetDir = ExtensionLoader.getPrivateExtensionDir(context)
            val pkgManager = context.packageManager
            @Suppress("DEPRECATION")
            var pkgName = pkgManager.getPackageArchiveInfo(tempFile.absolutePath, 0)?.packageName
            if (pkgName.isNullOrBlank()) {
                val meta = runCatching { runtime.PackageTools.getPackageMetadata(tempFile.toPath()) }.getOrNull()
                pkgName = meta?.pkgName
            }
            if (pkgName.isNullOrBlank()) {
                error("Invalid APK binary: package name missing")
            }

            val targetFile = File(targetDir, "$pkgName.ext")
            tempFile.copyTo(targetFile, overwrite = true)
            tempFile.delete()

            // Reload extension
            val result = ExtensionLoader.loadExtensionFromApkFile(context, targetFile)
            if (result is LoadResult.Success) {
                val installedExt = result.extension
                val currentList = _installedExtensions.value.filterNot { it.pkgName == installedExt.pkgName }
                val updatedList = currentList + installedExt
                _installedExtensions.value = updatedList
                sourceManager.registerSources(installedExt.sources)
                android.util.Log.i("watchAny-ExtensionManager", "Successfully installed extension $pkgName with ${installedExt.sources.size} sources")
                return installedExt
            } else {
                android.util.Log.e("watchAny-ExtensionManager", "Failed to load extension $pkgName from target file")
            }
        } catch (e: Throwable) {
            android.util.Log.e("watchAny-ExtensionManager", "Error installing extension from $apkUrl: ${e.message}", e)
            tempFile.delete()
        }
        return null
    }

    fun uninstallExtension(pkgName: String): Boolean {
        val targetDir = ExtensionLoader.getPrivateExtensionDir(context)
        val extFile = File(targetDir, "$pkgName.ext")
        if (extFile.exists()) extFile.delete()
        val apkFile = File(targetDir, "$pkgName.apk")
        if (apkFile.exists()) apkFile.delete()

        val current = _installedExtensions.value
        val targetExt = current.firstOrNull { it.pkgName == pkgName }
        if (targetExt != null) {
            sourceManager.unregisterSources(targetExt.sources)
            _installedExtensions.value = current.filterNot { it.pkgName == pkgName }
            android.util.Log.i("watchAny-ExtensionManager", "Successfully uninstalled extension $pkgName")
            return true
        }
        return true
    }

    fun getSource(sourceId: Long) = sourceManager.get(sourceId)
}
