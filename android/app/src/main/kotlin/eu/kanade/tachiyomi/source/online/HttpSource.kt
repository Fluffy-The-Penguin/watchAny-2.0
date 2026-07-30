package eu.kanade.tachiyomi.source.online

import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.asObservableSuccess
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.network.newCachelessCallWithProgress
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import rx.Observable
import tachiyomi.core.common.util.lang.awaitSingle
import uy.kohesive.injekt.injectLazy
import java.net.URI
import java.net.URISyntaxException
import java.security.MessageDigest

/**
 * Base class for HTTP-based manga sources matching the keiyoushi/extensions-lib contract.
 */
@Suppress("unused", "unused_parameter")
abstract class HttpSource : CatalogueSource {

    protected val network: NetworkHelper by injectLazy()

    abstract val baseUrl: String

    open fun getHomeUrl(): String = baseUrl

    open val versionId: Int = 1

    override val id: Long by lazy { generateId(name, lang, versionId) }

    val headers: Headers by lazy { headersBuilder().build() }

    open val client: OkHttpClient get() = network.client

    protected fun generateId(name: String, lang: String, versionId: Int): Long {
        val key = "${name.lowercase()}/$lang/$versionId"
        val bytes = MessageDigest.getInstance("MD5").digest(key.toByteArray())
        return (0..7).map { bytes[it].toLong() and 0xff shl 8 * (7 - it) }.reduce(Long::or) and Long.MAX_VALUE
    }

    protected open fun headersBuilder(): Headers.Builder = Headers.Builder().apply {
        add("User-Agent", network.defaultUserAgentProvider())
    }

    override fun toString(): String = "$name (${lang.uppercase()})"

    private fun getFullUrl(url: String): String {
        return when {
            url.startsWith("http://") || url.startsWith("https://") -> url
            url.startsWith("/") -> if (baseUrl.endsWith("/")) baseUrl.dropLast(1) + url else baseUrl + url
            else -> if (baseUrl.endsWith("/")) baseUrl + url else "$baseUrl/$url"
        }
    }

    // ─── Browse ───────────────────────────────────────────────────────────────

    override suspend fun getPopularManga(page: Int): MangasPage =
        fetchPopularManga(page).awaitSingle()

    override suspend fun getLatestUpdates(page: Int): MangasPage =
        fetchLatestUpdates(page).awaitSingle()

    override suspend fun getSearchManga(page: Int, query: String, filters: FilterList): MangasPage =
        fetchSearchManga(page, query, filters).awaitSingle()

    override fun fetchPopularManga(page: Int): Observable<MangasPage> =
        client.newCall(popularMangaRequest(page)).asObservableSuccess()
            .map { popularMangaParse(it) }

    protected open fun popularMangaRequest(page: Int): Request = throw UnsupportedOperationException()
    protected open fun popularMangaParse(response: Response): MangasPage = throw UnsupportedOperationException()

    override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> =
        client.newCall(searchMangaRequest(page, query, filters)).asObservableSuccess()
            .map { searchMangaParse(it) }

    protected open fun searchMangaRequest(page: Int, query: String, filters: FilterList): Request = throw UnsupportedOperationException()
    protected open fun searchMangaParse(response: Response): MangasPage = throw UnsupportedOperationException()

    override fun fetchLatestUpdates(page: Int): Observable<MangasPage> =
        client.newCall(latestUpdatesRequest(page)).asObservableSuccess()
            .map { latestUpdatesParse(it) }

    protected open fun latestUpdatesRequest(page: Int): Request = throw UnsupportedOperationException()
    protected open fun latestUpdatesParse(response: Response): MangasPage = throw UnsupportedOperationException()

    // ─── Manga details ────────────────────────────────────────────────────────

    override fun fetchMangaDetails(manga: SManga): Observable<SManga> =
        client.newCall(mangaDetailsRequest(manga)).asObservableSuccess()
            .map { mangaDetailsParse(it).apply { initialized = true } }

    open fun mangaDetailsRequest(manga: SManga): Request {
        return GET(getFullUrl(manga.url), headers)
    }

    protected open fun mangaDetailsParse(response: Response): SManga = throw UnsupportedOperationException()

    // ─── Chapter list ─────────────────────────────────────────────────────────

    override fun fetchChapterList(manga: SManga): Observable<List<SChapter>> =
        client.newCall(chapterListRequest(manga)).asObservableSuccess()
            .map { chapterListParse(it) }

    protected open fun chapterListRequest(manga: SManga): Request {
        return GET(getFullUrl(manga.url), headers)
    }

    protected open fun chapterListParse(response: Response): List<SChapter> = emptyList()

    // ─── Page list ────────────────────────────────────────────────────────────

    override fun fetchPageList(chapter: SChapter): Observable<List<Page>> =
        client.newCall(pageListRequest(chapter)).asObservableSuccess()
            .map { pageListParse(it) }

    protected open fun pageListRequest(chapter: SChapter): Request {
        return GET(getFullUrl(chapter.url), headers)
    }

    protected open fun pageListParse(response: Response): List<Page> = emptyList()

    // ─── Image URL ────────────────────────────────────────────────────────────

    open fun fetchImageUrl(page: Page): Observable<String> =
        client.newCall(imageUrlRequest(page)).asObservableSuccess()
            .map { imageUrlParse(it) }

    open suspend fun getImageUrl(page: Page): String = fetchImageUrl(page).awaitSingle()

    protected open fun imageUrlRequest(page: Page): Request = GET(getFullUrl(page.url), headers)

    protected open fun imageUrlParse(response: Response): String = throw UnsupportedOperationException()

    // ─── Raw image ────────────────────────────────────────────────────────────

    suspend fun getImage(page: Page): Response =
        client.newCachelessCallWithProgress(imageRequest(page), page).awaitSuccess()

    protected open fun imageRequest(page: Page): Request = GET(getFullUrl(page.imageUrl!!), headers)

    // ─── URL helpers ──────────────────────────────────────────────────────────

    fun SChapter.setUrlWithoutDomain(url: String) { this.url = getUrlWithoutDomain(url) }
    fun SManga.setUrlWithoutDomain(url: String) { this.url = getUrlWithoutDomain(url) }

    private fun getUrlWithoutDomain(orig: String): String {
        return try {
            val uri = URI(orig.replace(" ", "%20"))
            var out = uri.path ?: ""
            if (uri.query != null) out += "?" + uri.query
            if (uri.fragment != null) out += "#" + uri.fragment
            out
        } catch (_: URISyntaxException) { orig }
    }

    open fun getMangaUrl(manga: SManga): String = mangaDetailsRequest(manga).url.toString()
    open fun getChapterUrl(chapter: SChapter): String = pageListRequest(chapter).url.toString()

    @Deprecated("All modifications should be done when constructing the chapter")
    open fun prepareNewChapter(chapter: SChapter, manga: SManga) {}
}
