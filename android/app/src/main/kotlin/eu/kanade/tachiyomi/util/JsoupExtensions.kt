@file:JvmName("JsoupExtensionsKt")

package eu.kanade.tachiyomi.util

import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

fun Response.asJsoup(html: String? = null): Document {
    val bodyText = html ?: body.string()
    return Jsoup.parse(bodyText, request.url.toString())
}

fun Element.selectFirstOrThrow(cssQuery: String): Element {
    return selectFirst(cssQuery) ?: throw Exception("Element not found: $cssQuery")
}
