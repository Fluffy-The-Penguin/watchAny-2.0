package eu.kanade.tachiyomi.runtime.server

import eu.kanade.tachiyomi.runtime.loader.ExtensionManager
import eu.kanade.tachiyomi.runtime.loader.ExtensionLoader
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.SChapterImpl
import eu.kanade.tachiyomi.source.model.SMangaImpl
import io.javalin.Javalin
import io.javalin.http.Context
import okhttp3.OkHttpClient
import okhttp3.Request
import rx.Observable
import java.util.concurrent.TimeUnit

object ServerRoutes {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private fun <T> Observable<T>.await(): T = this.toBlocking().first()

    fun register(app: Javalin) {
        app.get("/api/health") { ctx ->
            ctx.json(mapOf("ok" to true, "status" to "running", "version" to "2.0.0"))
        }

        app.get("/api/installed") { ctx ->
            val sources = ExtensionLoader.getAllSources().map { s ->
                mapOf(
                    "id" to s.id.toString(),
                    "name" to s.name,
                    "lang" to s.lang,
                    "pkg" to ExtensionLoader.getPkgName(s.id.toString()),
                    "version" to "1.0.0"
                )
            }
            ctx.json(mapOf("ok" to true, "data" to sources))
        }

        app.get("/api/list") { ctx ->
            val available = ExtensionManager.getAvailableExtensions()
            ctx.json(mapOf("ok" to true, "data" to available))
        }

        val installHandler = io.javalin.http.Handler { ctx ->
            val pkgName = ctx.queryParam("pkg") ?: ctx.queryParam("pkgName") ?: ""
            if (pkgName.isEmpty()) {
                ctx.status(400).json(mapOf("ok" to false, "error" to "Missing pkg parameter"))
            } else {
                val success = ExtensionManager.installExtension(pkgName)
                ctx.json(mapOf("ok" to success))
            }
        }
        app.get("/api/install", installHandler)
        app.post("/api/install", installHandler)

        val uninstallHandler = io.javalin.http.Handler { ctx ->
            val pkgName = ctx.queryParam("pkg") ?: ctx.queryParam("pkgName") ?: ""
            val success = ExtensionManager.uninstallExtension(pkgName)
            ctx.json(mapOf("ok" to success))
        }
        app.get("/api/uninstall", uninstallHandler)
        app.post("/api/uninstall", uninstallHandler)

        app.get("/api/repos") { ctx ->
            ctx.json(mapOf("ok" to true, "data" to ExtensionManager.getRepositories()))
        }

        val addRepoHandler = io.javalin.http.Handler { ctx ->
            val url = ctx.queryParam("url") ?: ""
            if (url.isNotEmpty()) {
                ExtensionManager.addRepository(url)
            }
            ctx.json(mapOf("ok" to true))
        }
        app.get("/api/repos/add", addRepoHandler)
        app.post("/api/repos/add", addRepoHandler)

        app.get("/api/sources") { ctx ->
            val sources = ExtensionLoader.getAllSources().map { s ->
                mapOf(
                    "id" to s.id.toString(),
                    "name" to s.name,
                    "lang" to s.lang,
                    "supportsLatest" to ((s as? CatalogueSource)?.supportsLatest ?: false)
                )
            }
            ctx.json(mapOf("ok" to true, "data" to sources))
        }

        app.get("/api/popular") { ctx -> handleCatalogRequest(ctx, "popular") }
        app.get("/api/latest") { ctx -> handleCatalogRequest(ctx, "latest") }
        app.get("/api/search") { ctx -> handleCatalogRequest(ctx, "search") }

        app.get("/api/details") { ctx ->
            val sourceId = ctx.queryParam("sourceId") ?: ""
            val mangaUrl = ctx.queryParam("url") ?: ""
            val source = ExtensionLoader.getSource(sourceId)
            if (source == null) {
                ctx.status(404).json(mapOf("ok" to false, "error" to "Source not found"))
                return@get
            }

            try {
                val manga = SMangaImpl(url = mangaUrl)
                val details = source.fetchMangaDetails(manga).await()
                ctx.json(
                    mapOf(
                        "ok" to true,
                        "data" to mapOf(
                            "title" to details.title,
                            "author" to details.author,
                            "artist" to details.artist,
                            "description" to details.description,
                            "genre" to details.genre,
                            "status" to details.status,
                            "thumbnailUrl" to details.thumbnail_url
                        )
                    )
                )
            } catch (e: Exception) {
                println("[ServerRoutes] Error in /api/details: $e")
                e.printStackTrace()
                ctx.status(500).json(mapOf("ok" to false, "error" to "${e.javaClass.name}: ${e.message}"))
            }
        }

        app.get("/api/chapters") { ctx ->
            val sourceId = ctx.queryParam("sourceId") ?: ""
            val mangaUrl = ctx.queryParam("url") ?: ""
            val source = ExtensionLoader.getSource(sourceId)
            if (source == null) {
                ctx.status(404).json(mapOf("ok" to false, "error" to "Source not found"))
                return@get
            }

            try {
                val manga = SMangaImpl(url = mangaUrl)
                val chapters = source.fetchChapterList(manga).await()
                val mapped = chapters.map { ch ->
                    mapOf(
                        "url" to ch.url,
                        "name" to ch.name,
                        "chapterNumber" to ch.chapter_number,
                        "dateUpload" to ch.date_upload
                    )
                }
                ctx.json(mapOf("ok" to true, "data" to mapOf("chapters" to mapped)))
            } catch (e: Exception) {
                println("[ServerRoutes] Error in /api/chapters: $e")
                e.printStackTrace()
                ctx.status(500).json(mapOf("ok" to false, "error" to "${e.javaClass.name}: ${e.message}"))
            }
        }

        app.get("/api/pages") { ctx ->
            val sourceId = ctx.queryParam("sourceId") ?: ""
            val chapterUrl = ctx.queryParam("url") ?: ""
            val source = ExtensionLoader.getSource(sourceId)
            if (source == null) {
                ctx.status(404).json(mapOf("ok" to false, "error" to "Source not found"))
                return@get
            }

            try {
                val chapter = SChapterImpl(url = chapterUrl)
                val pages = source.fetchPageList(chapter).await()
                val mapped = pages.map { page ->
                    mapOf("imageUrl" to (page.imageUrl ?: page.url))
                }
                ctx.json(mapOf("ok" to true, "data" to mapOf("pages" to mapped)))
            } catch (e: Exception) {
                println("[ServerRoutes] Error in /api/pages: $e")
                e.printStackTrace()
                ctx.status(500).json(mapOf("ok" to false, "error" to "${e.javaClass.name}: ${e.message}"))
            }
        }

        app.get("/api/image") { ctx ->
            val imageUrl = ctx.queryParam("url") ?: ""
            if (imageUrl.isEmpty()) {
                ctx.status(400).result("Missing image url")
                return@get
            }

            try {
                // Derive a Referer from the image URL's origin to satisfy hotlink-protected CDNs
                val parsedUri = try { java.net.URI(imageUrl) } catch (_: Throwable) { null }
                val referer = if (parsedUri != null && parsedUri.host != null) {
                    "${parsedUri.scheme}://${parsedUri.host}/"
                } else {
                    "https://www.google.com/"
                }

                val req = Request.Builder()
                    .url(imageUrl)
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                    .header("Referer", referer)
                    .header("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
                    .header("Accept-Language", "en-US,en;q=0.9")
                    .build()
                val resp = client.newCall(req).execute()
                if (resp.code == 200) {
                    ctx.contentType(resp.header("Content-Type") ?: "image/jpeg")
                    val body = resp.body
                    if (body != null) {
                        ctx.result(body.byteStream())
                    } else {
                        ctx.status(404).result("Empty image body")
                    }
                } else {
                    ctx.status(resp.code).result("Upstream returned ${resp.code} for $imageUrl")
                }
            } catch (e: Exception) {
                ctx.status(500).result("Error fetching image: ${e.message}")
            }
        }
    }

    private fun handleCatalogRequest(ctx: Context, type: String) {
        val sourceId = ctx.queryParam("sourceId") ?: ""
        val page = ctx.queryParam("page")?.toIntOrNull() ?: 1
        val query = ctx.queryParam("q") ?: ""

        val source = ExtensionLoader.getSource(sourceId) as? CatalogueSource
        if (source == null) {
            ctx.status(404).json(mapOf("ok" to false, "error" to "CatalogueSource not found"))
            return
        }

        try {
            val pageResult = when (type) {
                "popular" -> source.fetchPopularManga(page).await()
                "latest" -> source.fetchLatestUpdates(page).await()
                "search" -> source.fetchSearchManga(page, query, FilterList()).await()
                else -> source.fetchPopularManga(page).await()
            }

            val mangas = pageResult.mangas.map { m ->
                mapOf(
                    "url" to m.url,
                    "title" to m.title,
                    "thumbnailUrl" to (m.thumbnail_url ?: "")
                )
            }

            ctx.json(mapOf("ok" to true, "data" to mapOf("mangas" to mangas, "hasNextPage" to pageResult.hasNextPage)))
        } catch (e: Throwable) {
            println("[ServerRoutes] Error in handleCatalogRequest: $e")
            e.printStackTrace()
            ctx.status(500).json(mapOf("ok" to false, "error" to "${e.javaClass.name}: ${e.message}"))
        }
    }
}
