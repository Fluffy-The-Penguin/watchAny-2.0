@file:JvmName("InjektKt")

package uy.kohesive.injekt

import uy.kohesive.injekt.api.InjektScope

val InjektScopeInstance: InjektScope = Injekt

@JvmName("getInjekt")
fun getInjekt(): InjektScope = InjektScopeInstance

inline fun <reified T : Any> injectLazy(): Lazy<T> = lazy { InjektScopeInstance.get<T>() }
