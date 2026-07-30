package uy.kohesive.injekt.api

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
import java.lang.reflect.Type
import java.util.concurrent.ConcurrentHashMap

open class InjektScope : InjektFactory<Any> {
    private val singletons = ConcurrentHashMap<Any, Any>()
    private val defaultContext = Application()
    private val defaultNetworkHelper = NetworkHelper()
    private val defaultJson = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        isLenient = true
    }

    init {
        singletons[Context::class.java] = defaultContext
        singletons[Application::class.java] = defaultContext
        singletons[NetworkHelper::class.java] = defaultNetworkHelper
        singletons[Json::class.java] = defaultJson
    }

    @Suppress("UNCHECKED_CAST")
    override fun getInstance(type: Type): Any {
        if (type is Class<*>) {
            val existing = singletons[type]
            if (existing != null) return existing

            if (Context::class.java.isAssignableFrom(type)) return defaultContext
            if (NetworkHelper::class.java.isAssignableFrom(type)) return defaultNetworkHelper
            if (Json::class.java.isAssignableFrom(type)) return defaultJson

            try {
                val created = type.getDeclaredConstructor().newInstance()
                singletons[type] = created
                return created
            } catch (_: Exception) {}
        }
        return defaultNetworkHelper
    }

    @Suppress("UNCHECKED_CAST")
    inline fun <reified T : Any> get(): T = getInstance(T::class.java) as T

    fun <T : Any> addSingleton(clazz: Class<T>, instance: T) {
        singletons[clazz] = instance
    }
}
