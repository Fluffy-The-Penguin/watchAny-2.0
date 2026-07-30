package eu.kanade.tachiyomi.runtime.loader

/**
 * Patched into okhttp3.Request.tag(Class) by the patchOkHttp Gradle task.
 *
 * dex2jar sometimes generates `new java/lang/Object` instead of `new x1` for obfuscated
 * Kotlin value classes. When z1.intercept calls request.tag(x1::class.java), it gets back
 * a plain Object and the subsequent CHECKCAST x1 fails. By returning null here instead of
 * the wrong Object, z1.intercept's `?: return chain.proceed(request)` safely falls through.
 */
@Suppress("UNCHECKED_CAST")
object OkHttpTagPatch {
    @JvmStatic
    fun safeTagGet(type: Class<*>, value: Any?): Any? {
        return if (value != null && type.isInstance(value)) value else null
    }
}
