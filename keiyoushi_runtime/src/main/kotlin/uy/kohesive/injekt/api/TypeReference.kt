package uy.kohesive.injekt.api

import java.lang.reflect.Type

interface TypeReference<T : Any> {
    val type: Type
}
