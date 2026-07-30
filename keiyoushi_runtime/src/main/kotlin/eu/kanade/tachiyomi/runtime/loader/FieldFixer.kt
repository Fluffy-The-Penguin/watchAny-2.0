package eu.kanade.tachiyomi.runtime.loader

import sun.misc.Unsafe

object FieldFixer {
    private val unsafe: Unsafe by lazy {
        val f = Unsafe::class.java.getDeclaredField("theUnsafe")
        f.isAccessible = true
        f.get(null) as Unsafe
    }

    @Volatile
    @JvmStatic
    var lastDecodedContainer: Any? = null

    @JvmStatic
    fun getNonNullTarget(targetClassName: String): Any? {
        val target = lastDecodedContainer
        if (target != null) {
            try {
                for (field in target::class.java.declaredFields) {
                    if (java.lang.reflect.Modifier.isStatic(field.modifiers)) continue
                    val offset = unsafe.objectFieldOffset(field)
                    if (field.type == List::class.java && unsafe.getObject(target, offset) == null) {
                        unsafe.putObject(target, offset, ArrayList<Any>())
                    }
                }
            } catch (_: Throwable) {}
            
            val cleanName = targetClassName.replace('/', '.')
            if (target.javaClass.name.endsWith(cleanName) || cleanName.endsWith(target.javaClass.name)) {
                return target
            }
        }
        return fixFieldVal(null, targetClassName)
    }

    @JvmStatic
    val dummyComp: java.util.Comparator<Any> = java.util.Comparator<Any> { _, _ -> 0 }

    @JvmStatic
    fun fixFieldVal(obj: Any?, targetClassName: String): Any? {
        if (targetClassName == "java/lang/Object" || targetClassName == "java.lang.Object") return obj
        if (targetClassName.contains("Comparator") || targetClassName.contains("Comparable")) {
            return dummyComp
        }
        if (targetClassName.contains("Json") || targetClassName == "m0" || targetClassName.endsWith(".m0")) {
            return eu.kanade.tachiyomi.network.defaultLenientJson
        }
        if (obj != null && obj !is java.lang.Object) return obj

        val cleanName = targetClassName.replace('/', '.')

        val loaders = mutableListOf<ClassLoader>()
        for (src in ExtensionLoader.getAllSources()) {
            loaders.add(src::class.java.classLoader)
        }
        val ctxCl = Thread.currentThread().contextClassLoader
        if (ctxCl != null) loaders.add(ctxCl)

        for (cl in loaders) {
            try {
                val clazz = Class.forName(cleanName, false, cl)
                if (clazz != java.lang.Object::class.java) {
                    for (fName in listOf("Companion", "INSTANCE", "a")) {
                        try {
                            val field = clazz.declaredFields.firstOrNull { it.name == fName && java.lang.reflect.Modifier.isStatic(it.modifiers) }
                            if (field != null) {
                                field.isAccessible = true
                                val valObj = field.get(null)
                                if (valObj != null && valObj.javaClass != java.lang.Object::class.java) {
                                    println("[FieldFixer] Fixed null/Object -> found static field $fName on $cleanName")
                                    return valObj
                                }
                            }
                        } catch (_: Throwable) {}
                    }
                    val inst = unsafe.allocateInstance(clazz)
                    println("[FieldFixer] Fixed null/Object -> allocated Unsafe instance of $cleanName")
                    return inst
                }
            } catch (_: Throwable) {}
        }
        return obj
    }
}
