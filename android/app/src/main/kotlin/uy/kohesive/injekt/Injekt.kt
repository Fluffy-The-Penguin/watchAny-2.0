package uy.kohesive.injekt

import uy.kohesive.injekt.api.InjektScope
import uy.kohesive.injekt.api.fullType
import kotlin.properties.ReadOnlyProperty
import kotlin.reflect.KProperty

@Volatile
var Injekt: InjektScope = InjektScope()

inline fun <reified T : Any> injectLazy(): Lazy<T> = lazy { Injekt.get(fullType<T>()) }
inline fun <reified T : Any> injectValue(): Lazy<T> = lazyOf(Injekt.get(fullType<T>()))
inline fun <reified T : Any> injectLazy(key: Any): Lazy<T> = lazy { Injekt.get(fullType<T>(), key) }
inline fun <reified T : Any> injectValue(key: Any): Lazy<T> = lazyOf(Injekt.get(fullType<T>(), key))

class InjektLazy<T : Any>(private val type: Class<T>) : ReadOnlyProperty<Any?, T> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): T = Injekt.get(type)
}
