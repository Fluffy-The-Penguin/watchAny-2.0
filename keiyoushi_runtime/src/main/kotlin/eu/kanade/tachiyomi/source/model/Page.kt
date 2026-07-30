package eu.kanade.tachiyomi.source.model

data class Page(
    val index: Int,
    val url: String = "",
    var imageUrl: String? = null,
    var uri: Any? = null
)

data class MangasPage(
    val mangas: List<SManga>,
    val hasNextPage: Boolean
)
