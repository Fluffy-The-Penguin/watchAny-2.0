package eu.kanade.tachiyomi.runtime.loader

import java.net.URL
import java.net.URLClassLoader

class ExtensionClassLoader(
    urls: Array<URL>,
    parent: ClassLoader
) : URLClassLoader(urls, parent) {

    override fun loadClass(name: String, resolve: Boolean): Class<*> {
        val isHostFrameworkClass = name.startsWith("android.") ||
                name.startsWith("androidx.") ||
                name.startsWith("eu.kanade.tachiyomi.network.") ||
                name.startsWith("eu.kanade.tachiyomi.source.") ||
                name.startsWith("eu.kanade.tachiyomi.lib.") ||
                name.startsWith("uy.kohesive.injekt.") ||
                name.startsWith("okhttp3.") ||
                name.startsWith("okio.") ||
                name.startsWith("org.jsoup.") ||
                // kotlinx.serialization intentionally NOT here — the extension's own
                // deserialization types (e.g. d0) extend these and must be co-loaded.
                // The host's kotlinx.serialization is shared via super.loadClass fallback.
                name.startsWith("rx.")

        if (isHostFrameworkClass) {
            try {
                val clazz = parent.loadClass(name)
                if (resolve) resolveClass(clazz)
                return clazz
            } catch (_: ClassNotFoundException) {}
        }

        return try {
            val clazz = findClass(name)
            if (resolve) resolveClass(clazz)
            clazz
        } catch (_: ClassNotFoundException) {
            super.loadClass(name, resolve)
        }
    }
}
