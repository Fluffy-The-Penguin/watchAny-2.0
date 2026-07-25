package uy.kohesive.injekt.api

import java.lang.reflect.GenericArrayType
import java.lang.reflect.ParameterizedType
import java.lang.reflect.Type
import java.lang.reflect.TypeVariable
import java.lang.reflect.WildcardType

@Suppress("UNCHECKED_CAST")
fun Type.erasedType(): Class<Any> {
    return when (this) {
        is Class<*> -> this as Class<Any>
        is ParameterizedType -> rawType.erasedType()
        is GenericArrayType -> java.lang.reflect.Array.newInstance(genericComponentType.erasedType(), 0).javaClass as Class<Any>
        is TypeVariable<*> -> Any::class.java as Class<Any>
        is WildcardType -> upperBounds.first().erasedType()
        else -> Any::class.java as Class<Any>
    }
}

inline fun <reified T : Any> typeRef(): FullTypeReference<T> = object : FullTypeReference<T>() {}
inline fun <reified T : Any> fullType(): FullTypeReference<T> = object : FullTypeReference<T>() {}

interface TypeReference<T> {
    val type: Type
}

abstract class FullTypeReference<T> protected constructor() : TypeReference<T> {
    override val type: Type = javaClass.genericSuperclass.let { superClass ->
        if (superClass is Class<*>) Any::class.java else (superClass as ParameterizedType).actualTypeArguments[0]
    }
}

interface InjektFactory {
    fun <R : Any> getInstance(forType: Type): R
    fun <R : Any> getInstanceOrElse(forType: Type, default: R): R
    fun <R : Any> getInstanceOrElse(forType: Type, default: () -> R): R
    fun <R : Any> getInstanceOrNull(forType: Type): R?

    fun <R : Any, K : Any> getKeyedInstance(forType: Type, key: K): R
    fun <R : Any, K : Any> getKeyedInstanceOrElse(forType: Type, key: K, default: R): R
    fun <R : Any, K : Any> getKeyedInstanceOrElse(forType: Type, key: K, default: () -> R): R
    fun <R : Any, K : Any> getKeyedInstanceOrNull(forType: Type, key: K): R?

    fun <R : Any> getLogger(expectedLoggerType: Type, byName: String): R
    fun <R : Any, T : Any> getLogger(expectedLoggerType: Type, forClass: Class<T>): R
}

open class InjektScope : InjektFactory {
    private val instances = linkedMapOf<String, Any>()
    private val keyedInstances = linkedMapOf<Pair<String, Any>, Any>()

    fun clear() = instances.clear()

    fun <T : Any> register(type: Class<T>, instance: T) {
        instances[type.name] = instance
    }

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> get(type: Class<T>): T {
        val name = type.name
        instances[name]?.let { return it as T }
        instances.entries.firstOrNull { (k, v) -> 
            k == name || k.endsWith(type.simpleName) || type.isInstance(v) || v.javaClass.name.endsWith(type.simpleName) 
        }?.let { return it.value as T }

        val created = type.getDeclaredConstructor().newInstance()
        instances[name] = created
        return created
    }


    @Suppress("UNCHECKED_CAST")
    fun <R : Any> get(forType: TypeReference<R>): R = get(forType.type.erasedType() as Class<R>)

    @Suppress("UNCHECKED_CAST")
    fun <R : Any> get(forType: TypeReference<R>, key: Any): R = getKeyedInstance(forType.type, key)

    @Suppress("UNCHECKED_CAST")
    override fun <R : Any> getInstance(forType: Type): R = get(forType.erasedType() as Class<R>)

    override fun <R : Any> getInstanceOrElse(forType: Type, default: R): R = getInstanceOrNull(forType) ?: default
    override fun <R : Any> getInstanceOrElse(forType: Type, default: () -> R): R = getInstanceOrNull(forType) ?: default()

    @Suppress("UNCHECKED_CAST")
    override fun <R : Any> getInstanceOrNull(forType: Type): R? {
        val type = forType.erasedType()
        val name = type.name
        instances[name]?.let { return it as R }
        return instances.entries.firstOrNull { (k, v) -> 
            k == name || k.endsWith(type.simpleName) || type.isInstance(v) || v.javaClass.name.endsWith(type.simpleName)
        }?.value as? R
    }


    @Suppress("UNCHECKED_CAST")
    override fun <R : Any, K : Any> getKeyedInstance(forType: Type, key: K): R {
        val name = forType.erasedType().name
        return keyedInstances.getOrPut(name to (key as Any)) { get(forType.erasedType() as Class<Any>) } as R
    }

    override fun <R : Any, K : Any> getKeyedInstanceOrElse(forType: Type, key: K, default: R): R = getKeyedInstanceOrNull(forType, key) ?: default
    override fun <R : Any, K : Any> getKeyedInstanceOrElse(forType: Type, key: K, default: () -> R): R = getKeyedInstanceOrNull(forType, key) ?: default()

    @Suppress("UNCHECKED_CAST")
    override fun <R : Any, K : Any> getKeyedInstanceOrNull(forType: Type, key: K): R? {
        val name = forType.erasedType().name
        return keyedInstances[name to (key as Any)] as? R
    }


    override fun <R : Any> getLogger(expectedLoggerType: Type, byName: String): R = getInstance(expectedLoggerType)
    override fun <R : Any, T : Any> getLogger(expectedLoggerType: Type, forClass: Class<T>): R = getInstance(expectedLoggerType)
}

inline fun <R : Any> InjektFactory.get(forType: TypeReference<R>): R = getInstance(forType.type)
inline fun <R : Any> InjektFactory.get(forType: TypeReference<R>, key: Any): R = getKeyedInstance(forType.type, key)

interface InjektRegistrar {
    fun InjektScope.registerInjectables() {}
}
