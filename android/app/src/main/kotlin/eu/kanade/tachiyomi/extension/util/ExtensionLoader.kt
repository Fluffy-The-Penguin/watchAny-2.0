package eu.kanade.tachiyomi.extension.util

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.pm.PackageInfoCompat
import eu.kanade.tachiyomi.extension.model.Extension
import eu.kanade.tachiyomi.extension.model.LoadResult
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.util.system.ChildFirstPathClassLoader
import runtime.PackageTools
import java.io.File

/**
 * Mihon & Komikku extension loader.
 * Loads both shared (system-installed) and private (app storage) extension APKs.
 */
object ExtensionLoader {

    private const val EXTENSION_FEATURE = "tachiyomi.extension"
    private const val METADATA_SOURCE_CLASS = "tachiyomi.extension.class"
    private const val METADATA_SOURCE_FACTORY = "tachiyomi.extension.factory"
    private const val METADATA_NSFW = "tachiyomi.extension.nsfw"
    private const val PRIVATE_EXTENSION_SUFFIX = "ext"

    @Suppress("DEPRECATION")
    private val PACKAGE_FLAGS = PackageManager.GET_CONFIGURATIONS or
        PackageManager.GET_META_DATA or
        PackageManager.GET_SIGNATURES or
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else 0)

    fun getPrivateExtensionDir(context: Context): File = File(context.filesDir, "exts").apply { mkdirs() }

    fun loadExtensions(context: Context): List<LoadResult> {
        PackageTools.injectDexAtStartup(context)
        val pkgManager = context.packageManager
        val results = mutableListOf<LoadResult>()

        // 1. Shared extensions (installed packages on system)
        val sharedInfoList = try {
            @Suppress("DEPRECATION")
            val installedPkgs = pkgManager.getInstalledPackages(PACKAGE_FLAGS)
            installedPkgs.filter { isPackageAnExtension(it) }
        } catch (e: Throwable) {
            emptyList()
        }

        for (pkgInfo in sharedInfoList) {
            val result = loadExtensionFromPkgInfo(context, pkgInfo, isShared = true)
            if (result != null) results.add(result)
        }

        // 2. Private extensions (APKs saved in exts directory)
        val privateFiles = getPrivateExtensionDir(context).listFiles()?.filter { it.isFile } ?: emptyList()
        for (file in privateFiles) {
            try {
                @Suppress("DEPRECATION")
                val pkgInfo = pkgManager.getPackageArchiveInfo(file.absolutePath, PACKAGE_FLAGS) ?: continue
                pkgInfo.applicationInfo?.sourceDir = file.absolutePath
                pkgInfo.applicationInfo?.publicSourceDir = file.absolutePath
                if (isPackageAnExtension(pkgInfo)) {
                    val result = loadExtensionFromPkgInfo(context, pkgInfo, isShared = false, apkPath = file.absolutePath)
                    if (result != null && results.none { (it as? LoadResult.Success)?.extension?.pkgName == pkgInfo.packageName }) {
                        results.add(result)
                    }
                }
            } catch (e: Throwable) {
                android.util.Log.e("watchAny-ExtensionLoader", "Failed to load private extension file ${file.name}: ${e.message}")
            }
        }

        return results
    }

    fun loadExtensionFromApkFile(context: Context, apkFile: File): LoadResult? {
        PackageTools.injectDexAtStartup(context)
        val pkgManager = context.packageManager
        @Suppress("DEPRECATION")
        val pkgInfo = pkgManager.getPackageArchiveInfo(apkFile.absolutePath, PACKAGE_FLAGS) ?: return null
        pkgInfo.applicationInfo?.sourceDir = apkFile.absolutePath
        pkgInfo.applicationInfo?.publicSourceDir = apkFile.absolutePath
        if (!isPackageAnExtension(pkgInfo)) return null
        return loadExtensionFromPkgInfo(context, pkgInfo, isShared = false, apkPath = apkFile.absolutePath)
    }

    private fun isPackageAnExtension(pkgInfo: PackageInfo): Boolean {
        val appInfo = pkgInfo.applicationInfo ?: return false
        val metaData = appInfo.metaData
        val hasFeature = pkgInfo.reqFeatures?.any { it.name == EXTENSION_FEATURE } == true
        val hasClassMeta = metaData?.containsKey(METADATA_SOURCE_CLASS) == true || metaData?.containsKey(METADATA_SOURCE_FACTORY) == true
        return hasFeature || hasClassMeta || pkgInfo.packageName.contains("tachiyomi.extension")
    }

    private fun loadExtensionFromPkgInfo(
        context: Context,
        pkgInfo: PackageInfo,
        isShared: Boolean,
        apkPath: String? = null
    ): LoadResult? {
        return try {
            val appInfo = pkgInfo.applicationInfo ?: return null
            val pkgName = pkgInfo.packageName
            val versionName = pkgInfo.versionName ?: "1.0"
            val versionCode = PackageInfoCompat.getLongVersionCode(pkgInfo)
            val extName = runCatching { context.packageManager.getApplicationLabel(appInfo).toString() }
                .getOrDefault(pkgName)
                .removePrefix("Tachiyomi: ")
                .removePrefix("Keiyoushi: ")
                .trim()

            val classLoader = ChildFirstPathClassLoader(
                apkPath ?: appInfo.sourceDir ?: "",
                appInfo.nativeLibraryDir,
                context.classLoader,
                context
            )

            val rawClasses = appInfo.metaData?.getString(METADATA_SOURCE_CLASS)
                ?: appInfo.metaData?.getString(METADATA_SOURCE_FACTORY)
                ?: ""

            val sourceClasses = rawClasses.split(';', ',', ' ')
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .map { if (it.startsWith('.')) pkgName + it else it }

            val sources = mutableListOf<Source>()
            for (className in sourceClasses) {
                try {
                    val clazz = classLoader.loadClass(className)
                    val instance = clazz.getDeclaredConstructor().newInstance()
                    when (instance) {
                        is CatalogueSource -> sources.add(instance)
                        is Source -> sources.add(instance)
                        is SourceFactory -> sources.addAll(instance.createSources())
                        else -> {
                            val createMethod = instance.javaClass.methods.firstOrNull { it.name == "createSources" }
                            if (createMethod != null) {
                                val created = createMethod.invoke(instance) as? List<*>
                                created?.filterIsInstance<Source>()?.let { sources.addAll(it) }
                            }
                        }
                    }
                } catch (e: Throwable) {
                    android.util.Log.e("watchAny-ExtensionLoader", "Error instantiating $className for $pkgName: ${e.message}", e)
                }
            }

            val lang = sources.firstOrNull()?.lang ?: "all"
            val isNsfw = appInfo.metaData?.getInt(METADATA_NSFW, 0) == 1

            val installed = Extension.Installed(
                name = extName,
                pkgName = pkgName,
                versionName = versionName,
                versionCode = versionCode,
                libVersion = 1.4,
                lang = lang,
                isNsfw = isNsfw,
                pkgFactory = appInfo.metaData?.getString(METADATA_SOURCE_FACTORY),
                sources = sources,
                isShared = isShared,
                apkPath = apkPath ?: appInfo.sourceDir
            )
            LoadResult.Success(installed)
        } catch (e: Throwable) {
            android.util.Log.e("watchAny-ExtensionLoader", "Failed to load extension ${pkgInfo.packageName}: ${e.message}", e)
            LoadResult.Error
        }
    }
}
