package eu.kanade.tachiyomi.util

import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

fun Response.asJsoup(html: String? = null): Document {
    val bodyStr = html ?: body?.string() ?: ""
    val baseUri = request.url.toString()
    return Jsoup.parse(bodyStr, baseUri)
}

fun Element.selectFirst(cssQuery: String): Element? {
    return select(cssQuery).first()
}
