package xyz.nulldev.androidcompat.replace.java.text

import java.text.DateFormatSymbols
import java.util.Locale

open class SimpleDateFormat : java.text.SimpleDateFormat {
    constructor() : super()
    constructor(pattern: String) : super(pattern)
    constructor(pattern: String, locale: Locale) : super(pattern, locale)
    constructor(pattern: String, formatSymbols: DateFormatSymbols) : super(pattern, formatSymbols)
}
