package uy.kohesive.injekt.api

import java.lang.reflect.Type

interface InjektFactory<R : Any> {
    fun getInstance(type: Type): Any
}
