package eu.kanade.tachiyomi.util.system

import android.content.Context
import dalvik.system.DexClassLoader
import dalvik.system.PathClassLoader
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.util.Enumeration

class ChildFirstPathClassLoader(
    dexPath: String,
    librarySearchPath: String?,
    parent: ClassLoader,
    context: Context? = null
) : PathClassLoader(dexPath, librarySearchPath, parent) {

    private val systemClassLoader: ClassLoader? = getSystemClassLoader()
    private var patchClassLoader: ClassLoader? = null

    init {
        if (context != null) {
            try {
                val dexFile = File(context.cacheDir, "generated_serializer.dex")
                if (!dexFile.exists() || dexFile.length() == 0L) {
                    context.assets.open("generated_serializer.dex").use { input ->
                        FileOutputStream(dexFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
                patchClassLoader = DexClassLoader(dexFile.absolutePath, context.codeCacheDir.absolutePath, null, parent)
            } catch (_: Throwable) {}
        }
    }

    override fun loadClass(name: String?, resolve: Boolean): Class<*> {
        if (name != null && (
            name.startsWith("kotlinx.serialization.") ||
            name.startsWith("eu.kanade.tachiyomi.") ||
            name.startsWith("tachiyomi.") ||
            name.startsWith("uy.kohesive.injekt.") ||
            name.startsWith("okhttp3.") ||
            name.startsWith("rx.") ||
            name.startsWith("org.jsoup.") ||
            name.startsWith("kotlin.")
        )) {
            val parentClass = runCatching { parent.loadClass(name) }.getOrNull()
            if (parentClass != null) {
                if (resolve) resolveClass(parentClass)
                return parentClass
            }
        }

        var c = findLoadedClass(name)

        if (c == null && systemClassLoader != null) {
            try {
                c = systemClassLoader.loadClass(name)
            } catch (_: ClassNotFoundException) {}
        }

        if (c == null) {
            c = try {
                findClass(name)
            } catch (_: ClassNotFoundException) {
                super.loadClass(name, resolve)
            }
        }

        if (resolve && c != null) {
            resolveClass(c)
        }

        return c ?: throw ClassNotFoundException(name)
    }

    override fun getResource(name: String?): URL? {
        return systemClassLoader?.getResource(name)
            ?: findResource(name)
            ?: super.getResource(name)
    }

    override fun getResources(name: String?): Enumeration<URL> {
        val systemUrls = systemClassLoader?.getResources(name)
        val localUrls = findResources(name)
        val parentUrls = parent?.getResources(name)
        val urls = buildList {
            while (systemUrls?.hasMoreElements() == true) {
                add(systemUrls.nextElement())
            }

            while (localUrls?.hasMoreElements() == true) {
                add(localUrls.nextElement())
            }

            while (parentUrls?.hasMoreElements() == true) {
                add(parentUrls.nextElement())
            }
        }
        return java.util.Collections.enumeration(urls)
    }
}
