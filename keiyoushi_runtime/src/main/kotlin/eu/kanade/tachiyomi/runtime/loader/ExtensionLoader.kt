package eu.kanade.tachiyomi.runtime.loader

import eu.kanade.tachiyomi.source.Source
import java.io.File
import java.util.jar.JarFile

object ExtensionLoader {
    // Maps sourceId -> source instance
    private val loadedSources = mutableMapOf<String, Source>()
    // Maps sourceId -> pkgName (e.g. eu.kanade.tachiyomi.extension.en.asurascans)
    private val sourcePkgNames = mutableMapOf<String, String>()

    fun loadJar(jarFile: File, pkgName: String? = null): Source? {
        if (!jarFile.exists()) return null
        try {
            val jar = JarFile(jarFile)
            val classNames = mutableListOf<String>()
            val entries = jar.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.name.endsWith(".class") && !entry.isDirectory) {
                    val className = entry.name
                        .removeSuffix(".class")
                        .replace('/', '.')
                    classNames.add(className)
                }
            }
            jar.close()

            val classLoader = ExtensionClassLoader(arrayOf(jarFile.toURI().toURL()), javaClass.classLoader)

            // Priority order for class selection (same logic as before, proven to work):
            // 1. Classes ending with "ExtensionGenerated" (Tachiyomi generator convention)
            // 2. Classes CONTAINING "Extension" anywhere in their name (works for AsuraScans etc.)
            // 3. Fallback: any class that is a Source when instantiated
            val mainClassName = classNames.firstOrNull { it.endsWith(".ExtensionGenerated") }
                ?: classNames.firstOrNull { name ->
                    // Match classes that contain "Extension" in their simple name but not inner/anonymous classes
                    val simple = name.substringAfterLast('.')
                    simple.contains("Extension") && !simple.contains("$")
                }
                ?: classNames.firstOrNull { name ->
                    // Broader fallback: class name contains "extension" in any segment (package or class)
                    name.contains("extension", ignoreCase = true) && !name.contains("$")
                }

            if (mainClassName != null) {
                try {
                    val clazz = classLoader.loadClass(mainClassName)
                    val instance = clazz.getDeclaredConstructor().newInstance()
                    if (instance is Source) {
                        println("[ExtensionLoader] Successfully loaded source: ${instance.name} (id: ${instance.id}) from class $mainClassName")
                        loadedSources[instance.id.toString()] = instance
                        if (pkgName != null) {
                            sourcePkgNames[instance.id.toString()] = pkgName
                        }
                        return instance
                    } else {
                        println("[ExtensionLoader] Class $mainClassName is not a Source instance, trying fallback scan")
                    }
                } catch (e: Throwable) {
                    println("[ExtensionLoader] Error instantiating $mainClassName: ${e.message}")
                    e.printStackTrace()
                }
            }

            // Last resort: scan all non-inner, non-interface classes for any Source implementation.
            // Use reflection on the Source interface to avoid classloader isolation issues with `is Source`.
            val sourceInterfaceName = Source::class.java.name
            for (className in classNames) {
                if (className.contains("$")) continue // skip inner/anonymous classes
                try {
                    val clazz = classLoader.loadClass(className)
                    if (clazz.isInterface) continue
                    if (java.lang.reflect.Modifier.isAbstract(clazz.modifiers)) continue

                    // Check if this class implements Source by checking interface names
                    val implementsSource = generateSequence<Class<*>>(clazz) { it.superclass }
                        .flatMap { c -> c.interfaces.asSequence() + sequenceOf(c) }
                        .any { it.name == sourceInterfaceName }

                    if (!implementsSource) continue

                    val noArgCtor = try {
                        clazz.getDeclaredConstructor()
                    } catch (_: NoSuchMethodException) { continue }

                    val instance = noArgCtor.newInstance()
                    if (instance is Source) {
                        println("[ExtensionLoader] (Fallback) Successfully loaded source: ${instance.name} (id: ${instance.id}) from class $className")
                        loadedSources[instance.id.toString()] = instance
                        if (pkgName != null) {
                            sourcePkgNames[instance.id.toString()] = pkgName
                        }
                        return instance
                    }
                } catch (_: Throwable) {
                    // Silently skip classes that fail to load or instantiate
                }
            }

            println("[ExtensionLoader] No Source implementation found in ${jarFile.name}")
        } catch (e: Exception) {
            println("[ExtensionLoader] Error reading JAR ${jarFile.name}: $e")
            e.printStackTrace()
        }
        return null
    }

    fun getSource(id: String): Source? {
        return loadedSources[id]
    }

    fun getAllSources(): List<Source> {
        return loadedSources.values.toList()
    }

    /** Returns the pkgName stored when the source was loaded, or reconstructs a best-guess from source metadata */
    fun getPkgName(sourceId: String): String {
        return sourcePkgNames[sourceId] ?: run {
            val source = loadedSources[sourceId]
            if (source != null) {
                "eu.kanade.tachiyomi.extension.${source.lang}.${source.name.lowercase().replace(" ", "")}"
            } else {
                ""
            }
        }
    }

    fun removeSource(pkgName: String): Boolean {
        val toRemove = sourcePkgNames.entries.filter { it.value == pkgName }.map { it.key }
        toRemove.forEach {
            loadedSources.remove(it)
            sourcePkgNames.remove(it)
        }
        return toRemove.isNotEmpty()
    }
}
