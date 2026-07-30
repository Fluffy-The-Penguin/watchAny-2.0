package eu.kanade.tachiyomi.network

import okhttp3.CacheControl
import okhttp3.Call
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import rx.Observable
import java.util.concurrent.TimeUnit
import kotlin.time.Duration
import eu.kanade.tachiyomi.runtime.loader.ExtensionLoader
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okio.BufferedSource
import kotlin.coroutines.suspendCoroutine

val defaultLenientJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
    coerceInputValues = true
    allowStructuredMapKeys = true
}

fun <T> Response.parseAs(serializer: DeserializationStrategy<T>): T {
    return this.body!!.source().use { source ->
        decodeFromBufferedSource(defaultLenientJson, serializer, source)
    }
}

// Primary overload matching the exact JVM signature extensions call:
// OkHttpExtensionsKt.decodeFromBufferedSource(Json, DeserializationStrategy, BufferedSource)
@Suppress("UNCHECKED_CAST")
private fun findMangaJsonArray(element: JsonElement): JsonArray? {
    if (element is JsonArray) {
        if (element.isNotEmpty() && element.first() is JsonObject) {
            val obj = element.first() as JsonObject
            if (obj.containsKey("slug") || obj.containsKey("title") || obj.containsKey("name") || obj.containsKey("id")) {
                return element
            }
        }
    } else if (element is JsonObject) {
        for ((_, v) in element.entries) {
            val res = findMangaJsonArray(v)
            if (res != null) return res
        }
    }
    return null
}

fun <T> decodeFromBufferedSource(
    json: Json,
    deserializer: DeserializationStrategy<T>,
    source: BufferedSource
): T {
    val jsonStr = source.readUtf8()
    val trimmed = jsonStr.trim()

    if (trimmed.startsWith("{")) {
        try {
            val rootObj = json.parseToJsonElement(trimmed)
            val arrayElem = findMangaJsonArray(rootObj)
            if (arrayElem != null) {
                println("[decodeFromBufferedSource] Parsing ${arrayElem.size} manga items dynamically")

                    val stackTrace = Thread.currentThread().stackTrace
                    val extCaller = stackTrace.firstOrNull { it.className.startsWith("eu.kanade.tachiyomi.extension") }
                    if (extCaller != null) {
                        val pkg = extCaller.className.substringBeforeLast('.')
                        val targetSource = ExtensionLoader.getAllSources().firstOrNull { it::class.java.name.startsWith(pkg) }
                        val targetCl = targetSource?.javaClass?.classLoader ?: Thread.currentThread().contextClassLoader
                        val loaders = mutableListOf(targetCl)
                        for (src in ExtensionLoader.getAllSources()) {
                            loaders.add(src::class.java.classLoader)
                        }
                        loaders.add(Thread.currentThread().contextClassLoader)

                        val rawSerName = try { deserializer.descriptor.serialName.substringAfterLast('.') } catch (_: Throwable) { null }
                        val cNames = mutableListOf<String>()
                        if (rawSerName != null && rawSerName !in listOf("e1", "x0", "l1", "y0", "t1", "u1")) {
                            cNames.add(rawSerName)
                            cNames.add("$pkg.$rawSerName")
                        }
                        when {
                            pkg.contains("asurascans") -> cNames.addAll(listOf("d0", "$pkg.d0"))
                            pkg.contains("flamecomics") -> {
                                if (extCaller.methodName == "b") {
                                    cNames.addAll(listOf("u0", "i1", "h1"))
                                } else {
                                    cNames.addAll(listOf("i1", "u0", "h1"))
                                }
                            }
                            else -> cNames.addAll(listOf("d0", "h1", "v1", "t0"))
                        }
                        val iNames = when {
                            pkg.contains("asurascans") -> listOf("y0", "$pkg.y0")
                            pkg.contains("flamecomics") -> listOf("l1", "x0", "$pkg.l1")
                            else -> listOf("y0", "l1", "u1", "t1", "$pkg.y0")
                        }

                        for (cl in loaders) {
                            for (cName in cNames) {
                                try {
                                    val containerClass = Class.forName(cName, false, cl)
                                    println("[decodeFromBufferedSource] Candidate containerClass: ${containerClass.name}, fields: ${containerClass.declaredFields.map { "${it.name}:${it.type.simpleName}" }}")
                                    var itemClass: Class<*>? = null
                                    for (iName in iNames) {
                                        try {
                                            itemClass = Class.forName(iName, false, cl)
                                            break
                                        } catch (_: Throwable) {}
                                    }

                                    if (itemClass == null) continue

                                    val unsafeField = sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe")
                                    unsafeField.isAccessible = true
                                    val unsafe = unsafeField.get(null) as sun.misc.Unsafe

                                    val itemList = ArrayList<Any>()
                                    println("[decodeFromBufferedSource] itemClass: ${itemClass.name}, declared fields: ${itemClass.declaredFields.map { "${it.name}:${it.type.simpleName}" }}")
                                    for (elem in arrayElem) {
                                        val itemObj = elem as? kotlinx.serialization.json.JsonObject ?: continue
                                        println("[decodeFromBufferedSource] elem keys: ${itemObj.keys}, sample: $itemObj")
                                        val itemInst = unsafe.allocateInstance(itemClass)

                                        val titleVal = itemObj["title"]?.jsonPrimitive?.contentOrNull
                                            ?: itemObj["name"]?.jsonPrimitive?.contentOrNull
                                        val slugVal = itemObj["slug"]?.jsonPrimitive?.contentOrNull
                                            ?: itemObj["url"]?.jsonPrimitive?.contentOrNull
                                        val coverVal = itemObj["cover"]?.jsonPrimitive?.contentOrNull
                                            ?: itemObj["image"]?.jsonPrimitive?.contentOrNull
                                            ?: itemObj["thumbnail"]?.jsonPrimitive?.contentOrNull
                                        var urlVal = itemObj["public_url"]?.jsonPrimitive?.contentOrNull
                                            ?: itemObj["url"]?.jsonPrimitive?.contentOrNull
                                            ?: itemObj["slug"]?.jsonPrimitive?.contentOrNull
                                            ?: (if (itemObj.containsKey("series_id")) "series/${itemObj["series_id"]?.jsonPrimitive?.contentOrNull}" else null)
                                            ?: itemObj["id"]?.jsonPrimitive?.contentOrNull

                                        if (pkg.contains("asurascans") && urlVal != null && !urlVal.startsWith("/") && !urlVal.startsWith("http")) {
                                            urlVal = "/$urlVal"
                                        }

                                         for (field in itemClass.declaredFields) {
                                             if (java.lang.reflect.Modifier.isStatic(field.modifiers)) continue
                                             val offset = unsafe.objectFieldOffset(field)
                                             val fName = field.name

                                             if (field.type == String::class.java) {
                                                 val strVal = if (pkg.contains("asurascans")) {
                                                     when (fName) {
                                                         "b" -> itemObj["title"]?.jsonPrimitive?.contentOrNull ?: titleVal ?: ""
                                                         "c" -> itemObj["cover"]?.jsonPrimitive?.contentOrNull ?: coverVal ?: ""
                                                         "a" -> itemObj["public_url"]?.jsonPrimitive?.contentOrNull ?: itemObj["slug"]?.jsonPrimitive?.contentOrNull ?: ""
                                                         "d" -> itemObj["description"]?.jsonPrimitive?.contentOrNull ?: ""
                                                         else -> try { itemObj[fName]?.jsonPrimitive?.contentOrNull ?: "" } catch (_: Throwable) { "" }
                                                     }
                                                 } else {
                                                     when (fName) {
                                                         "c" -> itemObj["title"]?.jsonPrimitive?.contentOrNull ?: titleVal ?: ""
                                                         "b" -> itemObj["slug"]?.jsonPrimitive?.contentOrNull ?: slugVal ?: ""
                                                         "a" -> itemObj["series_id"]?.jsonPrimitive?.contentOrNull ?: itemObj["id"]?.jsonPrimitive?.contentOrNull ?: urlVal ?: ""
                                                         "d" -> itemObj["description"]?.jsonPrimitive?.contentOrNull ?: ""
                                                         "e" -> itemObj["language"]?.jsonPrimitive?.contentOrNull ?: "English"
                                                         "i" -> itemObj["cover"]?.jsonPrimitive?.contentOrNull ?: coverVal ?: ""
                                                         else -> try { itemObj[fName]?.jsonPrimitive?.contentOrNull ?: "" } catch (_: Throwable) { "" }
                                                     }
                                                 }
                                                 unsafe.putObject(itemInst, offset, strVal)
                                             } else if (field.type == List::class.java || field.type == ArrayList::class.java) {
                                                 val listVal = ArrayList<String>()
                                                 val jsonArr = itemObj[fName] as? kotlinx.serialization.json.JsonArray
                                                     ?: (when (fName) {
                                                         "b" -> itemObj["categories"]
                                                         "f" -> itemObj["author"]
                                                         "g" -> itemObj["artist"]
                                                         "h" -> itemObj["publisher"]
                                                         else -> null
                                                     } as? kotlinx.serialization.json.JsonArray)

                                                 if (jsonArr != null) {
                                                     for (elem in jsonArr) {
                                                         elem.jsonPrimitive.contentOrNull?.let { listVal.add(it) }
                                                     }
                                                 }
                                                 unsafe.putObject(itemInst, offset, listVal)
                                             } else if (field.type.name == "int" || field.type.name == "java.lang.Integer") {
                                                 val intVal = try {
                                                     itemObj[fName]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                                                         ?: itemObj["popularityRank"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                                                         ?: itemObj["likes"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                                                         ?: itemObj["year"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                                                         ?: 0
                                                 } catch (_: Throwable) { 0 }
                                                 if (field.type.name == "int") {
                                                     unsafe.putInt(itemInst, offset, intVal)
                                                 } else {
                                                     unsafe.putObject(itemInst, offset, java.lang.Integer.valueOf(intVal))
                                                 }
                                             } else if (field.type.name == "long" || field.type.name == "java.lang.Long") {
                                                 val longVal = try {
                                                     itemObj[fName]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                                                         ?: itemObj["time"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                                                         ?: itemObj["last_edit"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                                                         ?: 0L
                                                 } catch (_: Throwable) { 0L }
                                                 if (field.type.name == "long") {
                                                     unsafe.putLong(itemInst, offset, longVal)
                                                 } else {
                                                     unsafe.putObject(itemInst, offset, java.lang.Long.valueOf(longVal))
                                                 }
                                             } else if (!field.type.isPrimitive) {
                                                 try {
                                                     if (field.name == "m" || field.type.isArray) {
                                                         val compType = field.type.componentType ?: Any::class.java
                                                         val arr = java.lang.reflect.Array.newInstance(compType, 5)
                                                         val dummyComp = java.util.Comparator<Any> { _, _ -> 0 }
                                                         val dummyLazy = object : kotlin.Lazy<Any> {
                                                             override val value: Any = dummyComp
                                                             override fun isInitialized(): Boolean = true
                                                         }
                                                         for (idx in 0 until 5) {
                                                             try {
                                                                 java.lang.reflect.Array.set(arr, idx, dummyLazy)
                                                             } catch (_: Throwable) {
                                                                 try {
                                                                     java.lang.reflect.Array.set(arr, idx, dummyComp)
                                                                 } catch (_: Throwable) {}
                                                             }
                                                         }
                                                         unsafe.putObject(itemInst, offset, arr)
                                                     } else {
                                                         val dummyComp = java.util.Comparator<Any> { _, _ -> 0 }
                                                         unsafe.putObject(itemInst, offset, dummyComp)
                                                     }
                                                 } catch (_: Throwable) {}
                                             }
                                         }
                                         itemList.add(itemInst)
                                     }

                                    val containerInst = unsafe.allocateInstance(containerClass)
                                    val buildIdVal = (rootObj as? kotlinx.serialization.json.JsonObject)?.get("buildId")?.jsonPrimitive?.contentOrNull
                                        ?: "default"

                                    for (field in containerClass.declaredFields) {
                                        if (java.lang.reflect.Modifier.isStatic(field.modifiers)) continue
                                        val offset = unsafe.objectFieldOffset(field)
                                        if (field.type == String::class.java) {
                                            unsafe.putObject(containerInst, offset, buildIdVal)
                                        } else if (field.type == List::class.java || field.type == ArrayList::class.java) {
                                            unsafe.putObject(containerInst, offset, itemList)
                                        } else if (!field.type.isPrimitive && !field.type.isArray && field.type != Any::class.java && field.type != Object::class.java) {
                                            try {
                                                val childInst = unsafe.allocateInstance(field.type)
                                                for (cf in field.type.declaredFields) {
                                                    if (java.lang.reflect.Modifier.isStatic(cf.modifiers)) continue
                                                    val coffset = unsafe.objectFieldOffset(cf)
                                                    if (cf.type == List::class.java || cf.type == ArrayList::class.java || cf.name == "a") {
                                                        unsafe.putObject(childInst, coffset, itemList)
                                                    }
                                                }
                                                unsafe.putObject(containerInst, offset, childInst)
                                            } catch (_: Throwable) {}
                                        }
                                    }

                                    println("[decodeFromBufferedSource] Successfully built dynamic ${containerClass.name} with buildId=$buildIdVal containing ${itemList.size} items")
                                    eu.kanade.tachiyomi.runtime.loader.FieldFixer.lastDecodedContainer = containerInst
                                    return containerInst as T
                                } catch (_: Throwable) {}
                            }
                        }
                    }
                }
        } catch (e: Throwable) {
            println("[decodeFromBufferedSource] Dynamic JSON parsing failed: $e")
        }
    }

    return json.decodeFromString(deserializer, jsonStr)
}

fun <T> decodeFromString(json: Json, deserializer: DeserializationStrategy<T>, jsonStr: String): T {
    val source = okio.Buffer().writeUtf8(jsonStr)
    return decodeFromBufferedSource(json, deserializer, source)
}

fun <T> Json.decodeFromResponse(deserializer: DeserializationStrategy<T>, response: Response): T {
    return decodeFromBufferedSource(this, deserializer, response.body!!.source())
}


fun OkHttpClient.newCacheControlForRequest(): CacheControl {
    return CacheControl.Builder().build()
}

fun Request.Builder.parseHeaders(headers: Headers): Request.Builder {
    return this.headers(headers)
}

fun Request.Builder.rateLimit(permits: Int, period: Long, unit: TimeUnit): Request.Builder {
    return this
}

// Static helper used by ApkLoader ASM rewrite for INVOKEVIRTUAL Request$Builder.tag(Class, Object)
fun safeSetTag(builder: Request.Builder, type: Class<*>?, tag: Any?): Request.Builder {
    return try {
        if (type != null) {
            val method = Request.Builder::class.java.getMethod("tag", Class::class.java, Object::class.java)
            method.invoke(builder, type, tag) as Request.Builder
        } else {
            builder.tag(tag)
        }
    } catch (_: Throwable) {
        builder.tag(tag)
    }
}

// Static helper used by ApkLoader ASM rewrite for INVOKEVIRTUAL Request.tag(Class)
fun safeTag(request: Request, type: Class<*>?): Any? {
    return try {
        if (type != null) {
            val method = Request::class.java.getMethod("tag", Class::class.java)
            method.invoke(request, type)
        } else {
            request.tag()
        }
    } catch (_: Throwable) {
        request.tag()
    }
}

fun ensureDescriptorPopulated(target: Any) {
    try {
        val targetClass = target.javaClass
        val descField = targetClass.declaredFields.firstOrNull { 
            java.lang.reflect.Modifier.isStatic(it.modifiers) && 
            (it.name == "descriptor" || it.name.contains("descriptor") || it.type.name.contains("SerialDescriptor"))
        }
        if (descField != null) {
            val builtDesc = kotlinx.serialization.descriptors.buildClassSerialDescriptor(targetClass.name) {
                element("public_url", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("slug", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("title", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("cover", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("id", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("name", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("image", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("thumbnail", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("url", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("data", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("latestEntries", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("pageProps", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
            }
            val unsafeField = sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe")
            unsafeField.isAccessible = true
            val unsafe = unsafeField.get(null) as sun.misc.Unsafe
            val base = unsafe.staticFieldBase(descField)
            val offset = unsafe.staticFieldOffset(descField)
            unsafe.putObject(base, offset, builtDesc)
            println("[ensureDescriptorPopulated] Successfully forced static descriptor on ${targetClass.name}")
        }
    } catch (e: Throwable) {
        println("[ensureDescriptorPopulated] Error populating descriptor for ${target.javaClass.name}: $e")
    }
}

@JvmStatic
@Suppress("UNCHECKED_CAST")
fun safeGetSerializer0(target: Any?, ownerClassName: String): kotlinx.serialization.KSerializer<Any> {
    val cleanOwner = ownerClassName.replace('/', '.')
    val realTarget = if (target == null || target.javaClass == java.lang.Object::class.java) {
        eu.kanade.tachiyomi.runtime.loader.FieldFixer.fixFieldVal(target, cleanOwner)
    } else target

    if (realTarget != null && realTarget.javaClass != java.lang.Object::class.java) {
        try {
            val m = realTarget.javaClass.methods.firstOrNull { it.name == "serializer" && it.parameterCount == 0 }
                ?: realTarget.javaClass.declaredMethods.firstOrNull { it.name == "serializer" && it.parameterCount == 0 }
            if (m != null) {
                m.isAccessible = true
                val res = m.invoke(realTarget)
                if (res is kotlinx.serialization.KSerializer<*>) {
                    return res as kotlinx.serialization.KSerializer<Any>
                }
            }
        } catch (_: Throwable) {}
    }

    return kotlinx.serialization.json.JsonElement.serializer() as kotlinx.serialization.KSerializer<Any>
}

@JvmStatic
@Suppress("UNCHECKED_CAST")
fun safeGetSerializer1(target: Any?, param: Any?, ownerClassName: String): kotlinx.serialization.KSerializer<Any> {
    val cleanOwner = ownerClassName.replace('/', '.')
    val realTarget = if (target == null || target.javaClass == java.lang.Object::class.java) {
        eu.kanade.tachiyomi.runtime.loader.FieldFixer.fixFieldVal(target, cleanOwner)
    } else target

    if (realTarget != null && realTarget.javaClass != java.lang.Object::class.java) {
        try {
            val m = realTarget.javaClass.methods.firstOrNull { it.name == "serializer" && it.parameterCount == 1 }
                ?: realTarget.javaClass.declaredMethods.firstOrNull { it.name == "serializer" && it.parameterCount == 1 }
            if (m != null) {
                m.isAccessible = true
                val res = m.invoke(realTarget, param)
                if (res is kotlinx.serialization.KSerializer<*>) {
                    return res as kotlinx.serialization.KSerializer<Any>
                }
            }
        } catch (_: Throwable) {}
    }

    if (param is kotlinx.serialization.KSerializer<*>) {
        return kotlinx.serialization.builtins.ListSerializer(param as kotlinx.serialization.KSerializer<Any>) as kotlinx.serialization.KSerializer<Any>
    }
    return kotlinx.serialization.json.JsonElement.serializer() as kotlinx.serialization.KSerializer<Any>
}


private fun createProxy(target: Any, targetInterface: Class<*>): Any {
    if (targetInterface.isInstance(target)) return target
    return java.lang.reflect.Proxy.newProxyInstance(
        targetInterface.classLoader ?: target.javaClass.classLoader,
        arrayOf(targetInterface)
    ) { _, method, args ->
        if (method.name == "getDescriptor" && (args == null || args.isEmpty())) {
            try {
                Class.forName(target.javaClass.name, true, target.javaClass.classLoader)
                val targetMethod = target.javaClass.methods.firstOrNull { it.name == "getDescriptor" && it.parameterCount == 0 }
                    ?: target.javaClass.declaredMethods.firstOrNull { it.name == "getDescriptor" && it.parameterCount == 0 }
                if (targetMethod != null) {
                    targetMethod.isAccessible = true
                    val desc = targetMethod.invoke(target)
                    if (desc != null) {
                        println("[createProxy] Successfully retrieved non-null descriptor from ${target.javaClass.name}")
                        return@newProxyInstance desc
                    }
                }
            } catch (e: Throwable) {
                println("[createProxy] Error getting descriptor from ${target.javaClass.name}: $e")
            }
            println("[createProxy] getDescriptor returned null for ${target.javaClass.name}, returning buildClassSerialDescriptor fallback")
            return@newProxyInstance kotlinx.serialization.descriptors.buildClassSerialDescriptor(target.javaClass.name) {
                element("data", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("latestEntries", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
                element("pageProps", kotlinx.serialization.json.JsonElement.serializer().descriptor, isOptional = true)
            }
        }

        val targetMethod = target.javaClass.methods.firstOrNull { it.name == method.name && it.parameterCount == method.parameterCount }
            ?: target.javaClass.declaredMethods.firstOrNull { it.name == method.name && it.parameterCount == method.parameterCount }
        if (targetMethod != null) {
            targetMethod.isAccessible = true
            targetMethod.invoke(target, *(args ?: emptyArray()))
        } else {
            null
        }
    }
}

fun customMaxAge(builder: CacheControl.Builder?, durationNs: Long): CacheControl.Builder {
    val b = builder ?: CacheControl.Builder()
    val seconds = if (durationNs > 100000000L) (durationNs / 1_000_000_000L).toInt() else durationNs.toInt()
    return b.maxAge(if (seconds <= 0) 300 else seconds, TimeUnit.SECONDS)
}

fun customMaxStale(builder: CacheControl.Builder?, durationNs: Long): CacheControl.Builder {
    val b = builder ?: CacheControl.Builder()
    val seconds = if (durationNs > 100000000L) (durationNs / 1_000_000_000L).toInt() else durationNs.toInt()
    return b.maxStale(if (seconds <= 0) 300 else seconds, TimeUnit.SECONDS)
}

fun customMinFresh(builder: CacheControl.Builder?, durationNs: Long): CacheControl.Builder {
    val b = builder ?: CacheControl.Builder()
    val seconds = if (durationNs > 100000000L) (durationNs / 1_000_000_000L).toInt() else durationNs.toInt()
    return b.minFresh(if (seconds <= 0) 300 else seconds, TimeUnit.SECONDS)
}

fun Call.asObservable(): Observable<Response> {
    return Observable.create { subscriber ->
        val call = this.clone()
        subscriber.add(rx.subscriptions.Subscriptions.create { call.cancel() })
        try {
            val response = call.execute()
            if (!subscriber.isUnsubscribed) {
                subscriber.onNext(response)
                subscriber.onCompleted()
            }
        } catch (e: Throwable) {
            if (!subscriber.isUnsubscribed) {
                subscriber.onError(e)
            }
        }
    }
}

fun Call.asObservableSuccess(): Observable<Response> {
    return asObservable().doOnNext { response ->
        if (!response.isSuccessful) {
            response.close()
            throw Exception("HTTP error ${response.code}")
        }
    }
}

suspend fun Call.await(): Response {
    return suspendCoroutine { continuation ->
        enqueue(object : okhttp3.Callback {
            override fun onResponse(call: Call, response: Response) {
                continuation.resumeWith(Result.success(response))
            }

            override fun onFailure(call: Call, e: java.io.IOException) {
                continuation.resumeWith(Result.failure(e))
            }
        })
    }
}

suspend fun Call.awaitSuccess(): Response {
    val response = await()
    if (!response.isSuccessful) {
        response.close()
        throw Exception("HTTP error ${response.code}")
    }
    return response
}

@JvmStatic
fun <T> safeSortedWith(iterable: Iterable<T>, comparator: Any?): List<T> {
    @Suppress("UNCHECKED_CAST")
    val comp = if (comparator is Comparator<*>) comparator as Comparator<T> else Comparator<T> { _, _ -> 0 }
    return try {
        iterable.sortedWith(comp)
    } catch (_: Throwable) {
        iterable.toList()
    }
}
