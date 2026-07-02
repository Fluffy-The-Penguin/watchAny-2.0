package runtime

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.util.asJsoup
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.io.InputStream
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import kotlin.io.path.Path
import kotlin.io.path.extension
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

private const val WEB_ASURA_PKG = "eu.kanade.tachiyomi.extension.en.asurascans"
private const val WEB_ASURA_SOURCE_ID = 6247824327199706550L
private const val SOURCE_REQUEST_TIMEOUT_MS = 35_000L

class LocalWebServer(private val context: Context, private val runtime: ExtensionRuntime, private val port: Int) : NanoHTTPD("127.0.0.1", port) {
    private val json = Json { prettyPrint = true }
    private val imageClient = OkHttpClient()
    private val sourceCache = mutableMapOf<Long, CachedSource>()

    override fun serve(session: IHTTPSession): Response {
        return try {
            route(session)
        } catch (error: Throwable) {
            sendJson(500, errorJson(error))
        }
    }

    private fun route(session: IHTTPSession): Response {
        return when (session.uri) {
            "/", "/index.html" -> sendText(200, "text/html; charset=utf-8", "<html><body>Manga Engine Natively running on Android</body></html>")
            "/api/health" -> api { buildJsonObject { put("status", "ok") } }
            "/api/repos" -> api { repos() }
            "/api/repos/add" -> api { addRepo(session) }
            "/api/repos/remove" -> api { removeRepo(session.requiredQuery("id")) }
            "/api/repos/toggle" -> api { toggleRepo(session) }
            "/api/repos/refresh" -> api { refreshRepo(session.requiredQuery("id")) }
            "/api/repos/refresh-all" -> api { refreshAllRepos() }
            "/api/repos/extensions" -> api { repoExtensions(session) }
            "/api/list" -> api { listExtensions(session.query()["q"].orEmpty()) }
            "/api/installed" -> api { installedExtensions() }
            "/api/install" -> api { installExtension(session.requiredQuery("pkg"), session.query()["repoId"]) }
            "/api/uninstall" -> api { uninstallExtension(session.requiredQuery("pkg")) }
            "/api/updates" -> api { updates() }
            "/api/update" -> api { updateExtension(session.requiredQuery("pkg")) }
            "/api/update-all" -> api { updateAllExtensions() }
            "/api/compat" -> api { compatibility(session) }
            "/api/probe" -> api { probe(session) }
            "/api/install-asura" -> api { installAsura() }
            "/api/sources" -> api { installedSources(session) }
            "/api/filters" -> api { filters(session) }
            "/api/search-all" -> api { searchAll(session) }
            "/api/search" -> api { search(session) }
            "/api/popular" -> api { popular(session) }
            "/api/latest" -> api { latest(session) }
            "/api/details" -> api { mangaDetails(session) }
            "/api/chapters" -> api { chapters(session) }
            "/api/pages" -> api { pages(session) }
            "/api/icon" -> extensionIcon(session)
            "/api/image" -> proxyImage(session)
            else -> sendText(404, "text/plain; charset=utf-8", "Not found")
        }
    }

    private fun api(block: () -> JsonElement): Response {
        return try {
            sendJson(200, buildJsonObject {
                put("ok", true)
                put("data", block())
            })
        } catch (error: Throwable) {
            sendJson(500, errorJson(error))
        }
    }

    private fun listExtensions(query: String): JsonElement {
        val q = query.trim()
        return buildJsonArray {
            runtime.index()
                .filter { extension ->
                    q.isBlank() || extension.name.contains(q, true) || extension.pkg.contains(q, true) ||
                        extension.sources.any { it.name.contains(q, true) || it.baseUrl.contains(q, true) }
                }
                .take(3000)
                .forEach { add(it.toJson()) }
        }
    }

    private fun installedExtensions(): JsonElement = buildJsonArray {
        runtime.installed().forEach { add(it.toJson()) }
    }

    private fun repos(): JsonElement = buildJsonArray {
        runtime.repos().forEach { add(it.toJson()) }
    }

    private fun addRepo(session: IHTTPSession): JsonElement {
        return runtime.addRepo(session.requiredQuery("url"), session.query()["name"]).toJson()
    }

    private fun removeRepo(id: String): JsonElement = buildJsonObject {
        put("removed", runtime.removeRepo(id))
    }

    private fun toggleRepo(session: IHTTPSession): JsonElement {
        val enabled = session.query()["enabled"]?.toBooleanStrictOrNull() ?: true
        return runtime.toggleRepo(session.requiredQuery("id"), enabled).toJson()
    }

    private fun refreshRepo(id: String): JsonElement = runtime.refreshRepo(id).toJson()

    private fun refreshAllRepos(): JsonElement = buildJsonArray {
        runtime.refreshAllRepos().forEach { add(it.toJson()) }
    }

    private fun repoExtensions(session: IHTTPSession): JsonElement {
        val query = session.query()["q"].orEmpty()
        val repoId = session.query()["repoId"]
        val limit = session.query()["limit"]?.toIntOrNull() ?: 200
        return buildJsonArray { runtime.repoExtensions(query, repoId, limit).forEach { add(it.toJson()) } }
    }

    private fun installExtension(pkg: String, repoId: String?): JsonElement = runtime.install(pkg, repoId).toJson()

    private fun uninstallExtension(pkg: String): JsonElement = buildJsonObject {
        put("removed", runtime.uninstall(pkg))
    }

    private fun updates(): JsonElement = buildJsonArray {
        runtime.updates().forEach { add(it.toJson()) }
    }

    private fun updateExtension(pkg: String): JsonElement = runtime.update(pkg).toJson()

    private fun updateAllExtensions(): JsonElement = buildJsonArray {
        runtime.updateAll().forEach { add(it.toJson()) }
    }

    private fun compatibility(session: IHTTPSession): JsonElement {
        val query = session.query()["q"].orEmpty()
        val limit = session.query()["limit"]?.toIntOrNull() ?: 20
        val offset = session.query()["offset"]?.toIntOrNull() ?: 0
        return buildJsonArray {
            runtime.checkCompatibility(query, limit, offset).forEach { add(it.toJson()) }
        }
    }

    private fun probe(session: IHTTPSession): JsonElement {
        val query = session.query()["q"].orEmpty()
        val searchQuery = session.query()["search"].orEmpty().ifBlank { "solo" }
        val limit = session.query()["limit"]?.toIntOrNull() ?: 1
        val offset = session.query()["offset"]?.toIntOrNull() ?: 0
        return buildJsonArray {
            runtime.probe(query, searchQuery, limit, offset).forEach { add(it.toJson()) }
        }
    }

    private fun installAsura(): JsonElement {
        return (runtime.installed().singleOrNull { it.pkg == WEB_ASURA_PKG } ?: runtime.install(WEB_ASURA_PKG)).toJson()
    }

    private fun installedSources(session: IHTTPSession): JsonElement = buildJsonArray {
        runtime.loadInstalledSources(session.query()["lang"]).forEach { source ->
            add(buildJsonObject {
                put("id", source.id.toString())
                put("lang", source.lang)
                put("name", source.name)
                put("supportsLatest", source.supportsLatest)
            })
        }
    }

    private fun searchAll(session: IHTTPSession): JsonElement {
        val query = session.query()["q"].orEmpty()
        val pageNumber = session.query()["page"]?.toIntOrNull() ?: 1
        val limit = session.query()["limit"]?.toIntOrNull() ?: 10
        return runtime.searchAll(query, pageNumber, limit, lang = session.query()["lang"]).toJson()
    }

    private fun search(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        val query = session.query()["q"].orEmpty()
        val pageNumber = session.query()["page"]?.toIntOrNull() ?: 1
        val filters = filterList(source, session.query()["filters"])
        session.query()["vrf"]?.takeIf { it.isNotBlank() }?.let { vrf ->
            if (source.name.equals("MangaFire", ignoreCase = true) && query.isNotBlank() && filters.isEmpty()) {
                return mangaFireSearch(source, query, pageNumber, vrf)
            }
        }
        val page = runBlocking { withTimeout(SOURCE_REQUEST_TIMEOUT_MS) { source.getSearchManga(pageNumber, query, filters) } }
        return mangaPageJson(source, page, "search")
    }

    private fun filters(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        val loadDynamic = session.query()["dynamic"]?.toBooleanStrictOrNull() ?: false
        val filterList = if (loadDynamic) dynamicFilterList(source) else safeFilterList(source, 2500) ?: FilterList()
        return buildJsonObject {
            put("sourceId", source.id.toString())
            put("sourceName", source.name)
            put("filters", buildJsonArray {
                filterList.forEachIndexed { index, filter -> add(filterJson(filter, index.toString())) }
            })
        }
    }

    private fun dynamicFilterList(source: CatalogueSource): FilterList {
        var list = safeFilterList(source, 2500) ?: return FilterList()
        repeat(10) {
            if (!hasPendingDynamicFilters(list)) return list
            Thread.sleep(500)
            list = safeFilterList(source, 1500) ?: return list
        }
        return list
    }

    private fun safeFilterList(source: CatalogueSource, timeoutMs: Long): FilterList? {
        val executor = Executors.newSingleThreadExecutor()
        val future = executor.submit<FilterList> { source.getFilterList() }
        return try {
            future.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (error: Throwable) {
            future.cancel(true)
            null
        } finally {
            executor.shutdownNow()
        }
    }

    private fun hasPendingDynamicFilters(filters: FilterList): Boolean {
        return filters.any { filter ->
            filter is eu.kanade.tachiyomi.source.model.Filter.Header && filter.name.contains("reset", ignoreCase = true) && filter.name.contains("tags", ignoreCase = true)
        }
    }

    private fun filterList(source: CatalogueSource, raw: String?): FilterList {
        if (raw.isNullOrBlank()) return FilterList()
        val values = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrElse { return FilterList() }
        val list = if (values.keys.any { it.contains('.') }) dynamicFilterList(source) else source.getFilterList()
        list.forEachIndexed { index, filter -> applyFilterValue(filter, index.toString(), values) }
        return list
    }

    private fun filterJson(filter: eu.kanade.tachiyomi.source.model.Filter<*>, id: String): JsonElement {
        return buildJsonObject {
            put("id", id)
            put("name", filter.name)
            when (filter) {
                is eu.kanade.tachiyomi.source.model.Filter.Header -> {
                    put("type", "header")
                }
                is eu.kanade.tachiyomi.source.model.Filter.Separator -> {
                    put("type", "separator")
                }
                is eu.kanade.tachiyomi.source.model.Filter.Select<*> -> {
                    put("type", "select")
                    put("state", filter.state)
                    put("values", buildJsonArray { filter.values.forEach { value -> add(JsonPrimitive(value.toString())) } })
                }
                is eu.kanade.tachiyomi.source.model.Filter.Text -> {
                    put("type", "text")
                    put("state", filter.state)
                }
                is eu.kanade.tachiyomi.source.model.Filter.CheckBox -> {
                    put("type", "checkbox")
                    put("state", filter.state)
                }
                is eu.kanade.tachiyomi.source.model.Filter.TriState -> {
                    put("type", "tristate")
                    put("state", filter.state)
                }
                is eu.kanade.tachiyomi.source.model.Filter.Sort -> {
                    put("type", "sort")
                    put("values", buildJsonArray { filter.values.forEach { value -> add(JsonPrimitive(value)) } })
                    filter.state?.let { selection ->
                        put("state", buildJsonObject {
                            put("index", selection.index)
                            put("ascending", selection.ascending)
                        })
                    }
                }
                is eu.kanade.tachiyomi.source.model.Filter.Group<*> -> {
                    put("type", "group")
                    put("children", buildJsonArray {
                        filter.state.forEachIndexed { index, child ->
                            if (child is eu.kanade.tachiyomi.source.model.Filter<*>) add(filterJson(child, "$id.$index"))
                        }
                    })
                }
            }
        }
    }

    private fun applyFilterValue(filter: eu.kanade.tachiyomi.source.model.Filter<*>, id: String, values: JsonObject) {
        val value = values[id]
        when (filter) {
            is eu.kanade.tachiyomi.source.model.Filter.Select<*> -> value?.jsonPrimitive?.intOrNull?.let { filter.state = it.coerceIn(0, filter.values.lastIndex.coerceAtLeast(0)) }
            is eu.kanade.tachiyomi.source.model.Filter.Text -> value?.jsonPrimitive?.content?.let { filter.state = it }
            is eu.kanade.tachiyomi.source.model.Filter.CheckBox -> value?.jsonPrimitive?.booleanOrNull?.let { filter.state = it }
            is eu.kanade.tachiyomi.source.model.Filter.TriState -> value?.jsonPrimitive?.intOrNull?.let { filter.state = it.coerceIn(0, 2) }
            is eu.kanade.tachiyomi.source.model.Filter.Sort -> (value as? JsonObject)?.let { objectValue ->
                val index = objectValue["index"]?.jsonPrimitive?.intOrNull ?: return@let
                val ascending = objectValue["ascending"]?.jsonPrimitive?.booleanOrNull ?: true
                filter.state = eu.kanade.tachiyomi.source.model.Filter.Sort.Selection(index.coerceIn(0, filter.values.lastIndex.coerceAtLeast(0)), ascending)
            }
            is eu.kanade.tachiyomi.source.model.Filter.Group<*> -> filter.state.forEachIndexed { index, child ->
                if (child is eu.kanade.tachiyomi.source.model.Filter<*>) applyFilterValue(child, "$id.$index", values)
            }
            else -> Unit
        }
    }

    private fun mangaFireSearch(source: CatalogueSource, query: String, pageNumber: Int, vrf: String): JsonElement {
        val httpSource = source as? HttpSource ?: error("MangaFire source is not HTTP-backed")
        val language = when (source.lang) {
            "es-419" -> "es-la"
            "pt-BR" -> "pt-br"
            else -> source.lang
        }
        val url = httpSource.baseUrl.toHttpUrl().newBuilder()
            .addPathSegment("filter")
            .addQueryParameter("keyword", query.trim())
            .addQueryParameter("language[]", language)
            .addQueryParameter("page", pageNumber.coerceAtLeast(1).toString())
            .addQueryParameter("vrf", vrf)
            .build()
        httpSource.client.newCall(GET(url, httpSource.headers)).execute().use { response ->
            check(response.isSuccessful) { "MangaFire search failed HTTP ${response.code}: $url" }
            val document = response.asJsoup()
            if (document.selectFirst("main h1")?.text()?.trim() == "403") error("MangaFire rejected this search request. Retry later or choose another source.")
            val entries = document.select(".original.card-lg .unit .inner")
            val hasNextPage = document.selectFirst(".page-item.active + .page-item .page-link") != null
            return buildJsonObject {
                put("sourceId", source.id.toString())
                put("sourceName", source.name)
                put("sourceLang", source.lang)
                put("kind", "search")
                put("hasNextPage", hasNextPage)
                put("mangas", buildJsonArray {
                    entries.forEach { element ->
                        val link = element.selectFirst(".info > a") ?: return@forEach
                        val title = link.ownText().ifBlank { link.text() }
                        if (title.isBlank()) return@forEach
                        add(buildJsonObject {
                            put("title", title)
                            put("url", urlWithoutDomain(link.attr("href")))
                            put("thumbnailUrl", element.selectFirst("img")?.attr("abs:src"))
                            put("description", "")
                        })
                    }
                })
            }
        }
    }

    private fun popular(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        val pageNumber = session.query()["page"]?.toIntOrNull() ?: 1
        val page = runBlocking { withTimeout(SOURCE_REQUEST_TIMEOUT_MS) { source.getPopularManga(pageNumber) } }
        return mangaPageJson(source, page, "popular")
    }

    private fun latest(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        check(source.supportsLatest) { "Source ${source.name} does not support latest updates" }
        val pageNumber = session.query()["page"]?.toIntOrNull() ?: 1
        val page = runBlocking { withTimeout(SOURCE_REQUEST_TIMEOUT_MS) { source.getLatestUpdates(pageNumber) } }
        return mangaPageJson(source, page, "latest")
    }

    private fun mangaPageJson(source: CatalogueSource, page: MangasPage, kind: String): JsonElement {
        return buildJsonObject {
            put("sourceId", source.id.toString())
            put("sourceName", source.name)
            put("sourceLang", source.lang)
            put("kind", kind)
            put("hasNextPage", page.hasNextPage)
            put("mangas", buildJsonArray {
                page.mangas.forEach { manga ->
                    add(buildJsonObject {
                        put("title", manga.title)
                        put("url", manga.url)
                        put("thumbnailUrl", manga.thumbnail_url)
                        put("description", manga.description)
                    })
                }
            })
        }
    }

    private fun mangaDetails(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        val mangaUrl = session.requiredQuery("url")
        val title = session.query()["title"].orEmpty().ifBlank { "Runtime Manga" }
        val manga = SManga.create().also {
            it.url = mangaUrl
            it.title = title
            session.query()["thumbnailUrl"]?.takeIf { value -> value.isNotBlank() }?.let { value -> it.thumbnail_url = value }
        }
        val details = runBlocking { withTimeout(SOURCE_REQUEST_TIMEOUT_MS) { source.getMangaDetails(manga) } }
        if (runCatching { details.url }.getOrNull().isNullOrBlank()) details.url = mangaUrl
        if (runCatching { details.title }.getOrNull().isNullOrBlank()) details.title = title
        return mangaDetailJson(source, details)
    }

    private fun mangaDetailJson(source: CatalogueSource, manga: SManga): JsonElement {
        return buildJsonObject {
            put("sourceId", source.id.toString())
            put("sourceName", source.name)
            put("sourceLang", source.lang)
            put("title", manga.title)
            put("url", manga.url)
            put("thumbnailUrl", manga.thumbnail_url)
            put("description", manga.description)
            put("artist", manga.artist)
            put("author", manga.author)
            put("status", manga.status)
            put("genre", manga.genre)
            put("genres", buildJsonArray {
                manga.getGenres()?.forEach { genre -> add(JsonPrimitive(genre)) }
            })
        }
    }

    private fun chapters(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        val mangaUrl = session.requiredQuery("url")
        val title = session.query()["title"].orEmpty().ifBlank { "Runtime Manga" }
        val manga = SManga.create().also {
            it.url = mangaUrl
            it.title = title
        }
        val chapters = runBlocking { source.getChapterList(manga) }
        return buildJsonObject {
            put("sourceId", source.id.toString())
            put("mangaUrl", mangaUrl)
            put("title", title)
            put("chapters", buildJsonArray {
                chapters.forEachIndexed { index, chapter ->
                    add(buildJsonObject {
                        put("index", index)
                        put("name", chapter.name)
                        put("url", chapter.url)
                        put("chapterNumber", chapter.chapter_number)
                        put("scanlator", chapter.scanlator)
                        put("dateUpload", chapter.date_upload)
                    })
                }
            })
        }
    }

    private fun pages(session: IHTTPSession): JsonElement {
        val source = source(session.requiredQuery("sourceId").toLong())
        val chapterUrl = session.requiredQuery("url")
        val chapter = SChapter.create().also {
            it.url = chapterUrl
            it.name = "Runtime Chapter"
        }
        val pages = runBlocking { source.getPageList(chapter) }
        return buildJsonObject {
            put("sourceId", source.id.toString())
            put("chapterUrl", chapterUrl)
            put("pages", buildJsonArray {
                pages.forEach { page ->
                    add(buildJsonObject {
                        put("index", page.index)
                        put("number", page.number)
                        put("url", page.url)
                        put("imageUrl", page.imageUrl)
                    })
                }
            })
        }
    }

    private fun source(sourceId: Long): CatalogueSource {
        val now = System.currentTimeMillis()
        synchronized(sourceCache) {
            sourceCache[sourceId]?.takeIf { now - it.loadedAt < 15 * 60 * 1000 }?.let { return it.source }
        }
        val runtimeSource = runtime.loadInstalledSources().firstOrNull { it.id == sourceId } ?: error("Catalogue source not found: $sourceId")
        synchronized(sourceCache) {
            sourceCache[sourceId] = CachedSource(runtimeSource, now)
        }
        return runtimeSource
    }

    private data class CachedSource(val source: CatalogueSource, val loadedAt: Long)

    private fun proxyImage(session: IHTTPSession): Response {
        val imageUrl = session.requiredQuery("url")
        val referer = imageReferer(imageUrl, session.query()["referer"])
        val origin = runCatching { URI(referer).let { "${it.scheme}://${it.host}" } }.getOrNull()
        val request = Request.Builder()
            .url(imageUrl)
            .header("User-Agent", NetworkHelper.DEFAULT_USER_AGENT)
            .header("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
            .header("Referer", referer)
            .apply { if (origin != null) header("Origin", origin) }
            .build()
        imageClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Image request failed: HTTP ${response.code}")
            val bytes = response.body.bytes()
            return sendBytes(200, response.header("Content-Type") ?: "application/octet-stream", bytes)
        }
    }

    private fun extensionIcon(session: IHTTPSession): Response {
        val pkg = session.requiredQuery("pkg")
        val installed = runtime.installed().singleOrNull { it.pkg == pkg } ?: error("Extension is not installed: $pkg")
        val iconPath = installed.iconPath ?: error("Extension icon is unavailable: $pkg")
        val path = Path(iconPath)
        if (!Files.exists(path)) error("Extension icon is missing: $pkg")
        return sendBytes(200, iconContentType(path.extension.lowercase()), Files.readAllBytes(path))
    }

    private fun iconContentType(extension: String): String = when (extension) {
        "webp" -> "image/webp"
        "jpg", "jpeg" -> "image/jpeg"
        "gif" -> "image/gif"
        else -> "image/png"
    }

    private fun imageReferer(imageUrl: String, explicitReferer: String?): String {
        if (!explicitReferer.isNullOrBlank()) return explicitReferer
        val uri = runCatching { URI(imageUrl) }.getOrNull()
        return when (uri?.host?.lowercase()) {
            "data.tnlycdn.com" -> "https://toonily.com/"
            "cdn.asurascans.com" -> "https://asurascans.com/"
            else -> uri?.let { "${it.scheme}://${it.host}/" } ?: "https://google.com/"
        }
    }

    private fun urlWithoutDomain(rawUrl: String): String {
        return runCatching {
            val uri = URI(rawUrl.replace(" ", "%20"))
            if (uri.scheme.isNullOrBlank()) return@runCatching rawUrl
            buildString {
                append(uri.path)
                if (uri.query != null) append('?').append(uri.query)
                if (uri.fragment != null) append('#').append(uri.fragment)
            }
        }.getOrDefault(rawUrl)
    }

    private fun sendJson(status: Int, body: JsonElement): Response {
        val res = newFixedLengthResponse(Response.Status.lookup(status), "application/json; charset=utf-8", json.encodeToString(JsonElement.serializer(), body))
        res.addHeader("Access-Control-Allow-Origin", "*")
        res.addHeader("Cache-Control", "no-store")
        return res
    }

    private fun sendText(status: Int, contentType: String, body: String): Response {
        val res = newFixedLengthResponse(Response.Status.lookup(status), contentType, body)
        res.addHeader("Access-Control-Allow-Origin", "*")
        res.addHeader("Cache-Control", "no-store")
        return res
    }

    private fun sendBytes(status: Int, contentType: String, bytes: ByteArray): Response {
        val res = newFixedLengthResponse(Response.Status.lookup(status), contentType, bytes.inputStream(), bytes.size.toLong())
        res.addHeader("Access-Control-Allow-Origin", "*")
        res.addHeader("Cache-Control", "no-store")
        return res
    }

    private fun errorJson(error: Throwable): JsonElement = buildJsonObject {
        put("ok", false)
        put("error", error.message?.takeIf { it.isNotBlank() } ?: error::class.qualifiedName ?: error.toString())
    }

    private fun IHTTPSession.query(): Map<String, String> {
        return parameters.mapValues { it.value.firstOrNull().orEmpty() }
    }

    private fun IHTTPSession.requiredQuery(name: String): String {
        return parameters[name]?.firstOrNull()?.takeIf { it.isNotBlank() } ?: error("Missing query parameter: $name")
    }

    private fun KeiyoushiExtension.toJson(): JsonElement = buildJsonObject {
        put("name", name)
        put("pkg", pkg)
        put("apk", apk)
        put("lang", lang)
        put("version", version)
        put("code", code)
        put("nsfw", nsfw)
        put("sources", buildJsonArray {
            sources.forEach { source ->
                add(buildJsonObject {
                    put("id", source.id.toString())
                    put("lang", source.lang)
                    put("name", source.name)
                    put("baseUrl", source.baseUrl)
                })
            }
        })
    }

    private fun ExtensionRepo.toJson(): JsonElement = buildJsonObject {
        put("id", id)
        put("name", name)
        put("indexUrl", indexUrl)
        put("apkBaseUrl", apkBaseUrl)
        put("enabled", enabled)
        put("lastFetchedAt", lastFetchedAt)
        put("lastError", lastError)
        put("extensionCount", extensionCount)
    }

    private fun IndexedExtension.toJson(): JsonElement = buildJsonObject {
        put("repo", repo.toJson())
        put("name", extension.name)
        put("pkg", extension.pkg)
        put("apk", extension.apk)
        put("lang", extension.lang)
        put("version", extension.version)
        put("code", extension.code)
        put("nsfw", extension.nsfw)
        put("sources", buildJsonArray {
            extension.sources.forEach { source ->
                add(buildJsonObject {
                    put("id", source.id.toString())
                    put("lang", source.lang)
                    put("name", source.name)
                    put("baseUrl", source.baseUrl)
                })
            }
        })
    }

    private fun InstalledExtension.toJson(): JsonElement = buildJsonObject {
        put("name", name)
        put("pkg", pkg)
        put("repoId", repoId)
        put("repoName", repoName)
        put("repoIndexUrl", repoIndexUrl)
        put("repoApkBaseUrl", repoApkBaseUrl)
        put("apk", apk)
        put("version", version)
        put("code", code)
        put("nsfw", nsfw)
        put("jarPath", jarPath)
        if (iconPath != null) put("iconUrl", "/api/icon?pkg=$pkg")
        put("sources", buildJsonArray {
            sources.forEach { source ->
                add(buildJsonObject {
                    put("id", source.id.toString())
                    put("lang", source.lang)
                    put("name", source.name)
                })
            }
        })
        put("sourceLoadErrors", buildJsonArray {
            sourceLoadErrors.forEach { error ->
                add(buildJsonObject {
                    put("className", error.className)
                    put("errorType", error.errorType)
                    put("message", error.message)
                    put("missingSymbol", error.missingSymbol)
                })
            }
        })
    }

    private fun ExtensionUpdate.toJson(): JsonElement = buildJsonObject {
        put("name", name)
        put("pkg", pkg)
        put("repoId", repoId)
        put("repoName", repoName)
        put("installedVersion", installedVersion)
        put("availableVersion", availableVersion)
        put("installedCode", installedCode)
        put("availableCode", availableCode)
        put("installedApk", installedApk)
        put("availableApk", availableApk)
    }

    private fun GlobalSearchResult.toJson(): JsonElement = buildJsonObject {
        put("query", query)
        put("groups", buildJsonArray { groups.forEach { add(it.toJson()) } })
        put("failures", buildJsonArray { failures.forEach { add(it.toJson()) } })
    }

    private fun SearchSourceGroup.toJson(): JsonElement = buildJsonObject {
        put("sourceId", sourceId.toString())
        put("sourceName", sourceName)
        put("sourceLang", sourceLang)
        put("extensionName", extensionName)
        put("extensionPkg", extensionPkg)
        put("ok", ok)
        put("hasNextPage", hasNextPage)
        put("error", error)
        put("results", buildJsonArray {
            results.forEach { result ->
                add(buildJsonObject {
                    put("title", result.title)
                    put("url", result.url)
                    put("thumbnailUrl", result.thumbnailUrl)
                    put("description", result.description)
                })
            }
        })
    }

    private fun CompatibilityResult.toJson(): JsonElement = buildJsonObject {
        put("name", name)
        put("pkg", pkg)
        put("version", version)
        put("ok", ok)
        put("errorType", errorType)
        put("errorMessage", errorMessage)
        put("missingSymbol", missingSymbol)
        put("sources", buildJsonArray {
            sources.forEach { source ->
                add(buildJsonObject {
                    put("id", source.id.toString())
                    put("lang", source.lang)
                    put("name", source.name)
                })
            }
        })
        put("sourceLoadErrors", buildJsonArray {
            sourceLoadErrors.forEach { error ->
                add(buildJsonObject {
                    put("className", error.className)
                    put("errorType", error.errorType)
                    put("message", error.message)
                    put("missingSymbol", error.missingSymbol)
                })
            }
        })
    }

    private fun ProbeResult.toJson(): JsonElement = buildJsonObject {
        put("name", name)
        put("pkg", pkg)
        put("version", version)
        put("sourceId", sourceId?.toString())
        put("sourceName", sourceName)
        put("sourceLang", sourceLang)
        put("ok", ok)
        put("mangaTitle", mangaTitle)
        put("mangaUrl", mangaUrl)
        put("chapterName", chapterName)
        put("chapterUrl", chapterUrl)
        put("resultCount", resultCount)
        put("chapterCount", chapterCount)
        put("pageCount", pageCount)
        put("stages", buildJsonArray {
            stages.forEach { stage ->
                add(buildJsonObject {
                    put("name", stage.name)
                    put("ok", stage.ok)
                    put("message", stage.message)
                })
            }
        })
    }

    private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())
}
