package uy.kohesive.injekt.api

import java.lang.reflect.ParameterizedType
import java.lang.reflect.Type

abstract class FullTypeReference<T : Any> protected constructor() {
    val type: Type = (javaClass.genericSuperclass as ParameterizedType).actualTypeArguments[0]
}
