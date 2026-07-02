package runtime

import android.content.Context
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.lang.reflect.InvocationTargetException
import java.net.URI
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import kotlin.io.path.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.name
import kotlin.io.path.readText
import kotlin.io.path.writeText

class ExtensionRuntime(private val context: Context, private val root: Path) {
    private val client = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }
    private val apkDir = root.resolve("apk")
    private val iconDir = root.resolve("icons")
    private val installedFile = root.resolve("installed.json")
    private val reposFile = root.resolve("repos.json")

    fun index(): List<KeiyoushiExtension> = indexedExtensions(useDefaultFallback = true).map { it.extension }

    fun installed(): List<InstalledExtension> = readInstalled()

    fun repos(): List<ExtensionRepo> = readRepos()

    fun addRepo(url: String, name: String? = null): ExtensionRepo {
        root.createDirectories()
        val normalized = normalizeRepo(url, name)
        val existing = readRepos().filterNot { it.id == normalized.id || it.indexUrl.equals(normalized.indexUrl, true) }
        val fetched = refreshRepoMetadata(normalized)
        writeRepos(existing + fetched)
        return fetched
    }

    fun removeRepo(id: String): Boolean {
        val repos = readRepos()
        val next = repos.filterNot { it.id == id }
        writeRepos(next)
        return next.size != repos.size
    }

    fun toggleRepo(id: String, enabled: Boolean): ExtensionRepo {
        val repos = readRepos()
        val current = repos.singleOrNull { it.id == id } ?: error("Repository not found: $id")
        val updated = current.copy(enabled = enabled)
        writeRepos(repos.map { if (it.id == id) updated else it })
        return updated
    }

    fun refreshRepo(id: String): ExtensionRepo {
        val repos = readRepos()
        val current = repos.singleOrNull { it.id == id } ?: error("Repository not found: $id")
        val refreshed = refreshRepoMetadata(current)
        writeRepos(repos.map { if (it.id == id) refreshed else it })
        return refreshed
    }

    fun refreshAllRepos(): List<ExtensionRepo> {
        val repos = readRepos()
        val refreshed = repos.map { repo -> refreshRepoMetadata(repo) }
        writeRepos(refreshed)
        return refreshed
    }

    fun repoExtensions(query: String = "", repoId: String? = null, limit: Int = 200): List<IndexedExtension> {
        val q = query.trim()
        return indexedExtensions(useDefaultFallback = false)
            .filter { indexed -> repoId.isNullOrBlank() || indexed.repo.id == repoId }
            .filter { indexed ->
                val extension = indexed.extension
                q.isBlank() || extension.pkg.contains(q, true) || extension.name.contains(q, true) ||
                    extension.sources.any { it.name.contains(q, true) || it.baseUrl.contains(q, true) }
            }
            .take(limit.coerceAtLeast(1))
    }

    fun install(pkgName: String, repoId: String? = null): InstalledExtension {
        val extension = indexedExtensions(useDefaultFallback = true)
            .filter { repoId.isNullOrBlank() || it.repo.id == repoId }
            .firstOrNull { it.extension.pkg == pkgName }
            ?: error("Package not found in configured extension repos: $pkgName")
        return loadExtension(extension, persist = true)
    }

    fun updates(): List<ExtensionUpdate> {
        return readInstalled().mapNotNull { current ->
            val latest = latestForInstalled(current) ?: return@mapNotNull null
            if (!current.hasUpdate(latest.extension)) return@mapNotNull null
            ExtensionUpdate(
                name = latest.extension.name.removePrefix("Tachiyomi: ").trim(),
                pkg = current.pkg,
                repoId = latest.repo.id,
                repoName = latest.repo.name,
                installedVersion = current.version,
                availableVersion = latest.extension.version,
                installedCode = current.installedCode(),
                availableCode = latest.extension.code,
                installedApk = current.apk,
                availableApk = latest.extension.apk,
            )
        }
    }

    fun update(pkgName: String): InstalledExtension {
        val installed = readInstalled().singleOrNull { it.pkg == pkgName } ?: error("Package is not installed: $pkgName")
        val latest = latestForInstalled(installed) ?: error("Package not found in configured extension repos: $pkgName")
        if (!installed.hasUpdate(latest.extension)) return installed
        return loadExtension(latest, persist = true)
    }

    fun updateAll(): List<InstalledExtension> {
        val installed = readInstalled()
        return installed.mapNotNull { current ->
            val latest = latestForInstalled(current) ?: return@mapNotNull null
            if (current.hasUpdate(latest.extension)) loadExtension(latest, persist = true) else null
        }
    }

    fun uninstall(pkgName: String): Boolean {
        val installed = readInstalled()
        val current = installed.singleOrNull { it.pkg == pkgName } ?: return false
        writeInstalled(installed.filterNot { it.pkg == pkgName })
        runCatching { Files.deleteIfExists(apkDir.resolve(current.apk)) }
        runCatching { Files.deleteIfExists(Path(current.jarPath)) }
        current.iconPath?.let { icon -> runCatching { Files.deleteIfExists(Path(icon)) } }
        return true
    }

    fun checkCompatibility(query: String, limit: Int = 20, offset: Int = 0): List<CompatibilityResult> {
        return matchingExtensions(query, limit, offset).map { indexed ->
            val extension = indexed.extension
            try {
                val loaded = loadExtension(indexed, persist = false)
                val sourceError = loaded.sourceLoadErrors.firstOrNull()
                val noSources = loaded.sources.isEmpty()
                CompatibilityResult(
                    name = extension.name.removePrefix("Tachiyomi: ").trim(),
                    pkg = extension.pkg,
                    version = extension.version,
                    ok = !noSources && sourceError == null,
                    sources = loaded.sources,
                    sourceLoadErrors = loaded.sourceLoadErrors,
                    errorType = when {
                        noSources -> "NoSources"
                        sourceError != null -> sourceError.errorType
                        else -> null
                    },
                    errorMessage = when {
                        noSources -> "No catalogue sources loaded"
                        sourceError != null -> sourceError.message
                        else -> null
                    },
                    missingSymbol = sourceError?.missingSymbol,
                )
            } catch (error: Throwable) {
                val detail = error.compatibilityDetail()
                CompatibilityResult(
                    name = extension.name.removePrefix("Tachiyomi: ").trim(),
                    pkg = extension.pkg,
                    version = extension.version,
                    ok = false,
                    errorType = detail.type,
                    errorMessage = detail.message,
                    missingSymbol = detail.missingSymbol,
                )
            }
        }
    }

    fun probe(query: String, searchQuery: String = "solo", limit: Int = 1, offset: Int = 0): List<ProbeResult> {
        return matchingExtensions(query, limit, offset).map { extension -> probeExtension(extension, searchQuery) }
    }

    private fun probeExtension(indexed: IndexedExtension, searchQuery: String): ProbeResult {
        val extension = indexed.extension
        val stages = mutableListOf<ProbeStage>()
        val installed = try {
            loadExtension(indexed, persist = true).also {
                stages += ProbeStage("load", true, "Loaded ${it.sources.size} source(s)")
            }
        } catch (error: Throwable) {
            return ProbeResult.fromFailure(extension, stages + ProbeStage.failure("load", error))
        }

        val selected = installed.sources.firstOrNull { it.lang == "en" } ?: installed.sources.firstOrNull()
        if (selected == null) {
            return ProbeResult.fromFailure(extension, stages + ProbeStage("source", false, "No catalogue sources exported"))
        }

        val source = try {
            loadInstalledSources().single { it.id == selected.id }.also {
                stages += ProbeStage("source", true, "${it.name} (${it.lang}, ${it.id})")
            }
        } catch (error: Throwable) {
            return ProbeResult.fromFailure(extension, stages + ProbeStage.failure("source", error), selected)
        }

        val discovered = try {
            discoverMangaPage(source, searchQuery).also { (stage, page) ->
                stages += ProbeStage(stage, true, "${page.mangas.size} result(s) for '$searchQuery'")
            }
        } catch (error: Throwable) {
            return ProbeResult.fromFailure(extension, stages + ProbeStage.failure("search", error), selected)
        }
        val searchPage = discovered.second
        val manga = searchPage.mangas.firstOrNull()
        if (manga == null) {
            return ProbeResult(
                name = extension.name.removePrefix("Tachiyomi: ").trim(),
                pkg = extension.pkg,
                version = extension.version,
                sourceId = selected.id,
                sourceName = selected.name,
                sourceLang = selected.lang,
                ok = false,
                stages = stages + ProbeStage("chapters", false, "Search returned no manga to test"),
                resultCount = 0,
            )
        }

        val chapters = try {
            runBlocking { source.getChapterList(manga) }.also {
                stages += ProbeStage("chapters", true, "${it.size} chapter(s) for ${manga.title}")
            }
        } catch (error: Throwable) {
            return ProbeResult.fromFailure(extension, stages + ProbeStage.failure("chapters", error), selected, manga.title, manga.url, searchPage.mangas.size)
        }
        if (chapters.isEmpty()) {
            return ProbeResult(
                name = extension.name.removePrefix("Tachiyomi: ").trim(),
                pkg = extension.pkg,
                version = extension.version,
                sourceId = selected.id,
                sourceName = selected.name,
                sourceLang = selected.lang,
                ok = false,
                stages = stages + ProbeStage("pages", false, "No chapters to test"),
                mangaTitle = manga.title,
                mangaUrl = manga.url,
                resultCount = searchPage.mangas.size,
                chapterCount = 0,
            )
        }

        val chapterCandidates = (chapters.take(3) + chapters.takeLast(3)).distinctBy { it.url }
        var lastPageError: Throwable? = null
        for (chapter in chapterCandidates) {
            try {
                val pages = runBlocking { source.getPageList(chapter) }
                stages += ProbeStage("pages", true, "${pages.size} page(s) for ${chapter.name}")
                return ProbeResult(
                    name = extension.name.removePrefix("Tachiyomi: ").trim(),
                    pkg = extension.pkg,
                    version = extension.version,
                    sourceId = selected.id,
                    sourceName = selected.name,
                    sourceLang = selected.lang,
                    ok = true,
                    stages = stages,
                    mangaTitle = manga.title,
                    mangaUrl = manga.url,
                    chapterName = chapter.name,
                    chapterUrl = chapter.url,
                    resultCount = searchPage.mangas.size,
                    chapterCount = chapters.size,
                    pageCount = pages.size,
                )
            } catch (error: Throwable) {
                lastPageError = error
            }
        }

        return ProbeResult.fromFailure(
            extension = extension,
            stages = stages + ProbeStage.failure("pages", lastPageError ?: IllegalStateException("No chapter candidate could be tested")),
            source = selected,
            mangaTitle = manga.title,
            mangaUrl = manga.url,
            resultCount = searchPage.mangas.size,
            chapterCount = chapters.size,
        )
    }

    fun searchAll(query: String, page: Int = 1, perSourceLimit: Int = 10, timeoutMs: Long = 15000, lang: String? = null): GlobalSearchResult {
        val q = query.trim()
        if (q.isBlank()) return GlobalSearchResult(query = q, groups = emptyList())
        val installedSources = sourceInstallInfoById()
        val langFilter = languageFilter(lang)
        return runBlocking {
            val sources = loadInstalledSources(langFilter)
            val groups = coroutineScope {
                sources.map { source ->
                    async {
                        val info = installedSources[source.id]
                        val base = SearchSourceGroup(
                            sourceId = source.id,
                            sourceName = source.name,
                            sourceLang = source.lang,
                            extensionName = info?.extensionName ?: source.name,
                            extensionPkg = info?.extensionPkg.orEmpty(),
                            ok = false,
                        )
                        val result = withTimeoutOrNull(timeoutMs) {
                            runCatching { source.getSearchManga(page.coerceAtLeast(1), q, FilterList()) }
                        } ?: return@async base.copy(error = "Timed out after ${timeoutMs}ms")
                        result.fold(
                            onSuccess = { mangasPage ->
                                base.copy(
                                    ok = true,
                                    hasNextPage = mangasPage.hasNextPage,
                                    results = mangasPage.mangas.take(perSourceLimit.coerceAtLeast(1)).map { manga ->
                                        SearchMangaResult(
                                            title = manga.title,
                                            url = manga.url,
                                            thumbnailUrl = manga.thumbnail_url,
                                            description = manga.description,
                                        )
                                    },
                                )
                            },
                            onFailure = { error ->
                                val detail = error.compatibilityDetail()
                                base.copy(error = detail.missingSymbol ?: detail.message)
                            },
                        )
                    }
                }.awaitAll()
            }
            GlobalSearchResult(query = q, groups = groups, failures = groups.filter { !it.ok })
        }
    }

    private fun discoverMangaPage(source: CatalogueSource, searchQuery: String): Pair<String, MangasPage> {
        return try {
            "search" to runBlocking { source.getSearchManga(1, searchQuery, FilterList()) }
        } catch (error: Throwable) {
            if (!error.isSearchUnsupported()) throw error
            runCatching { "popular" to runBlocking { source.getPopularManga(1) } }
                .recoverCatching {
                    if (source.supportsLatest) "latest" to runBlocking { source.getLatestUpdates(1) } else throw it
                }
                .getOrThrow()
        }
    }

    private fun Throwable.isSearchUnsupported(): Boolean {
        val message = generateSequence(this) { it.cause }.mapNotNull { it.message }.joinToString("\n").lowercase()
        return "search is not supported" in message || "full-text search is not supported" in message
    }

    private fun matchingExtensions(query: String, limit: Int, offset: Int = 0): List<IndexedExtension> {
        val q = query.trim()
        return indexedExtensions(useDefaultFallback = true)
            .filter { indexed ->
                val extension = indexed.extension
                q.isBlank() || extension.pkg.equals(q, true) || extension.pkg.contains(q, true) ||
                    extension.name.contains(q, true) || extension.sources.any { it.name.contains(q, true) || it.baseUrl.contains(q, true) }
            }
            .drop(offset.coerceAtLeast(0))
            .take(limit.coerceAtLeast(1))
    }

    private fun InstalledExtension.hasUpdate(latest: KeiyoushiExtension): Boolean {
        val currentCode = installedCode()
        return version != latest.version || apk != latest.apk || (currentCode != null && latest.code > currentCode)
    }

    private fun InstalledExtension.installedCode(): Long? {
        if (code != null) return code
        return runCatching { PackageTools.getPackageMetadata(apkDir.resolve(apk)).versionCode.takeIf { it > 0L } }.getOrNull()
    }

    private fun latestForInstalled(installed: InstalledExtension): IndexedExtension? {
        val repos = readRepos().filter { it.enabled }
        val repo = repos.firstOrNull { repo ->
            (!installed.repoId.isNullOrBlank() && repo.id == installed.repoId) ||
                (!installed.repoIndexUrl.isNullOrBlank() && repo.indexUrl.equals(installed.repoIndexUrl, true))
        } ?: repoForInstalled(installed)
        return repo.cachedExtensions.firstOrNull { it.pkg == installed.pkg }?.let { IndexedExtension(repo, it) }
    }

    private fun repoForInstalled(installed: InstalledExtension): ExtensionRepo {
        if (!installed.repoIndexUrl.isNullOrBlank()) {
            return ExtensionRepo(
                id = installed.repoId ?: repoId(installed.repoIndexUrl),
                name = installed.repoName ?: repoNameFromUrl(installed.repoIndexUrl),
                indexUrl = installed.repoIndexUrl,
                apkBaseUrl = installed.repoApkBaseUrl ?: apkBaseUrlFromIndexUrl(installed.repoIndexUrl),
            )
        }
        if (!installed.repoId.isNullOrBlank()) readRepos().firstOrNull { it.id == installed.repoId }?.let { return it }
        return defaultRepo()
    }

    private fun sourceInstallInfoById(): Map<Long, SourceInstallInfo> {
        return readInstalled().flatMap { installed ->
            installed.sources.map { source ->
                source.id to SourceInstallInfo(installed.name, installed.pkg)
            }
        }.toMap()
    }

    private fun indexedExtensions(useDefaultFallback: Boolean): List<IndexedExtension> {
        val repos = readRepos().filter { it.enabled }
        if (repos.isNotEmpty() && repos.all { it.cachedExtensions.isEmpty() }) {
            repos.forEach { repo ->
                try {
                    refreshRepo(repo.id)
                } catch (e: Throwable) {
                    android.util.Log.e("watchAny-ExtensionRuntime", "Failed to force refresh empty repo: ${e.message}", e)
                }
            }
            return readRepos().filter { it.enabled }.flatMap { repo -> repo.cachedExtensions.map { extension -> IndexedExtension(repo, extension) } }
        }
        return repos.flatMap { repo -> repo.cachedExtensions.map { extension -> IndexedExtension(repo, extension) } }
    }

    private fun refreshRepoMetadata(repo: ExtensionRepo): ExtensionRepo {
        return try {
            val extensions = KeiyoushiIndex(client).fetch(repo.indexUrl)
            repo.copy(lastFetchedAt = System.currentTimeMillis(), lastError = null, extensionCount = extensions.size, cachedExtensions = extensions)
        } catch (error: Throwable) {
            repo.copy(lastFetchedAt = System.currentTimeMillis(), lastError = error.message ?: error.toString())
        }
    }

    private fun normalizeRepo(url: String, name: String?): ExtensionRepo {
        val raw = url.trim().ifBlank { error("Repository URL is required") }
        val uri = URI(raw)
        check(uri.scheme == "https" || uri.scheme == "http") { "Repository URL must be http or https" }
        val indexUrl = if (raw.endsWith("index.min.json", ignoreCase = true)) raw else raw.trimEnd('/') + "/index.min.json"
        return ExtensionRepo(
            id = repoId(indexUrl),
            name = name?.trim()?.takeIf { it.isNotBlank() } ?: repoNameFromUrl(indexUrl),
            indexUrl = indexUrl,
            apkBaseUrl = apkBaseUrlFromIndexUrl(indexUrl),
        )
    }

    private fun defaultRepo(): ExtensionRepo = ExtensionRepo(
        id = repoId(DEFAULT_REPO_INDEX_URL),
        name = "Keiyoushi",
        indexUrl = DEFAULT_REPO_INDEX_URL,
        apkBaseUrl = DEFAULT_REPO_APK_BASE_URL,
    )

    private fun repoId(indexUrl: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(indexUrl.lowercase().toByteArray())
        return "repo-" + digest.take(8).joinToString("") { "%02x".format(it) }
    }

    private fun repoNameFromUrl(indexUrl: String): String {
        return runCatching {
            val uri = URI(indexUrl)
            val host = uri.host?.removePrefix("www.").orEmpty()
            when {
                indexUrl.contains("keiyoushi/extensions", true) -> "Keiyoushi"
                host.isNotBlank() -> host
                else -> "Extension Repo"
            }
        }.getOrDefault("Extension Repo")
    }

    private fun apkBaseUrlFromIndexUrl(indexUrl: String): String {
        return indexUrl.substringBeforeLast('/', missingDelimiterValue = indexUrl.trimEnd('/')).trimEnd('/') + "/apk/"
    }

    private fun readRepos(): List<ExtensionRepo> {
        if (!reposFile.exists()) {
            val default = defaultRepo()
            try {
                writeRepos(listOf(default))
                java.util.concurrent.Executors.newSingleThreadExecutor().execute {
                    try {
                        refreshRepo(default.id)
                    } catch (e: Throwable) {
                        android.util.Log.e("watchAny-ExtensionRuntime", "Failed to auto-refresh default repo: ${e.message}", e)
                    }
                }
            } catch (e: Throwable) {
                android.util.Log.e("watchAny-ExtensionRuntime", "Failed to write default repo: ${e.message}", e)
            }
            return listOf(default)
        }
        return try {
            json.decodeFromString(reposFile.readText())
        } catch (e: Throwable) {
            emptyList()
        }
    }

    private fun writeRepos(repos: List<ExtensionRepo>) {
        root.createDirectories()
        reposFile.writeText(json.encodeToString(repos))
    }

    private fun loadExtension(indexed: IndexedExtension, persist: Boolean): InstalledExtension {
        val extension = indexed.extension
        val repo = indexed.repo
        root.createDirectories()
        apkDir.createDirectories()
        iconDir.createDirectories()
        val apkPath = apkDir.resolve(extension.apk)
        download(indexed.apkUrl, apkPath)

        val metadata = PackageTools.getPackageMetadata(apkPath)
        check(metadata.features.contains(PackageTools.EXTENSION_FEATURE)) { "APK is not a Tachiyomi extension" }
        val libVersion = metadata.versionName.substringBeforeLast('.').toDoubleOrNull() ?: 0.0
        check(libVersion in PackageTools.LIB_VERSION_MIN..PackageTools.LIB_VERSION_MAX) { "Unsupported extension lib version: $libVersion" }
        
        val iconPath = PackageTools.extractIcon(apkPath, iconDir)?.toAbsolutePath()?.toString()

        val classNames = metadata.sourceClasses.flatMap { raw -> raw.split(';') }
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .map { if (it.startsWith('.')) metadata.pkgName + it else it }

        val loaded = loadSourcesFromApkDetailed(apkPath, classNames)
        val sourceErrors = loaded.errors.toMutableList()
        val sourceMetadata = loaded.sources.mapNotNull { source ->
            runCatching { InstalledSource(source.id, source.lang, source.name) }
                .onFailure { error -> sourceErrors += SourceLoadError.from(source.javaClass.name, error) }
                .getOrNull()
        }
        val installed = InstalledExtension(
            name = extension.name.removePrefix("Tachiyomi: ").trim(),
            pkg = extension.pkg,
            repoId = repo.id,
            repoName = repo.name,
            repoIndexUrl = repo.indexUrl,
            repoApkBaseUrl = repo.apkBaseUrl,
            apk = extension.apk,
            version = extension.version,
            code = extension.code,
            nsfw = metadata.nsfw,
            jarPath = apkPath.toAbsolutePath().toString(), // Storing APK path in jarPath field
            iconPath = iconPath,
            sourceClasses = classNames,
            sources = sourceMetadata,
            sourceLoadErrors = sourceErrors,
        )
        if (persist) {
            val next = readInstalled().filterNot { it.pkg == installed.pkg } + installed
            writeInstalled(next)
        }
        return installed
    }

    fun loadInstalledSources(lang: String? = null): List<CatalogueSource> {
        val langFilter = languageFilter(lang)
        return readInstalled().flatMap { installed -> loadSourcesFromApk(Path(installed.jarPath), installed.sourceClasses) }
            .filter { source -> languageMatches(source.lang, langFilter) }
    }

    private fun loadSourcesFromApk(apkPath: Path, classNames: List<String>): List<CatalogueSource> {
        return loadSourcesFromApkDetailed(apkPath, classNames).sources
    }

    private fun loadSourcesFromApkDetailed(apkPath: Path, classNames: List<String>): LoadedSources {
        val sources = mutableListOf<CatalogueSource>()
        val errors = mutableListOf<SourceLoadError>()
        classNames.forEach { className ->
            try {
                val instance = PackageTools.loadExtensionClass(context, apkPath, className)
                when (instance) {
                    is CatalogueSource -> sources += instance
                    is Source -> sources += listOf(instance).filterIsInstance<CatalogueSource>()
                    is SourceFactory -> sources += instance.createSources().filterIsInstance<CatalogueSource>()
                    else -> errors += SourceLoadError(className, "UnknownType", "Unknown source class type ${instance.javaClass.name}")
                }
            } catch (error: Throwable) {
                errors += SourceLoadError.from(className, error)
            }
        }
        return LoadedSources(sources, errors)
    }

    private fun languageFilter(lang: String?): String? {
        val value = lang?.trim()?.lowercase()?.takeIf { it.isNotBlank() }
        return if (value == null || value == "all" || value == "*") null else value
    }

    private fun languageMatches(sourceLang: String, langFilter: String?): Boolean {
        if (langFilter == null) return true
        val lang = sourceLang.trim().lowercase()
        return lang == langFilter || lang == "all" || lang.isBlank()
    }

    private fun readInstalled(): List<InstalledExtension> {
        if (!installedFile.exists()) return emptyList()
        return json.decodeFromString(installedFile.readText())
    }

    private fun writeInstalled(installed: List<InstalledExtension>) {
        root.createDirectories()
        installedFile.writeText(json.encodeToString(installed))
    }

    private fun download(url: String, target: Path) {
        if (target.exists() && Files.size(target) > 0) return
        val request = Request.Builder().url(url).build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "Download failed ${response.code}: $url" }
            Files.newOutputStream(target).use { output -> response.body.byteStream().copyTo(output) }
        }
    }
}

private data class CompatibilityDetail(val type: String, val message: String, val missingSymbol: String? = null)

private fun Throwable.compatibilityDetail(): CompatibilityDetail {
    val flattened = generateSequence(this) { error ->
        when (error) {
            is InvocationTargetException -> error.targetException
            else -> error.cause
        }
    }.toList()
    val relevant = flattened.firstOrNull {
        it is NoClassDefFoundError || it is ClassNotFoundException || it is NoSuchMethodError || it is NoSuchFieldError
    } ?: flattened.lastOrNull() ?: this
    val missing = when (relevant) {
        is NoClassDefFoundError -> relevant.message?.replace('/', '.')
        is ClassNotFoundException -> relevant.message
        is NoSuchMethodError -> relevant.message
        is NoSuchFieldError -> relevant.message
        else -> null
    }
    return CompatibilityDetail(
        type = relevant.javaClass.simpleName,
        message = relevant.message ?: relevant.toString(),
        missingSymbol = missing,
    )
}

@Serializable
data class ExtensionRepo(
    val id: String,
    val name: String,
    val indexUrl: String,
    val apkBaseUrl: String,
    val enabled: Boolean = true,
    val lastFetchedAt: Long? = null,
    val lastError: String? = null,
    val extensionCount: Int? = null,
    val cachedExtensions: List<KeiyoushiExtension> = emptyList(),
)

data class IndexedExtension(
    val repo: ExtensionRepo,
    val extension: KeiyoushiExtension,
) {
    val apkUrl: String get() = repo.apkBaseUrl.trimEnd('/') + "/" + extension.apk
}

private data class SourceInstallInfo(val extensionName: String, val extensionPkg: String)

private data class LoadedSources(val sources: List<CatalogueSource>, val errors: List<SourceLoadError>)

@Serializable
data class SourceLoadError(
    val className: String,
    val errorType: String,
    val message: String,
    val missingSymbol: String? = null,
) {
    companion object {
        fun from(className: String, error: Throwable): SourceLoadError {
            val detail = error.compatibilityDetail()
            return SourceLoadError(
                className = className,
                errorType = detail.type,
                message = detail.missingSymbol ?: detail.message,
                missingSymbol = detail.missingSymbol,
            )
        }
    }
}

data class GlobalSearchResult(
    val query: String,
    val groups: List<SearchSourceGroup>,
    val failures: List<SearchSourceGroup> = emptyList(),
)

data class SearchSourceGroup(
    val sourceId: Long,
    val sourceName: String,
    val sourceLang: String,
    val extensionName: String,
    val extensionPkg: String,
    val ok: Boolean,
    val hasNextPage: Boolean = false,
    val results: List<SearchMangaResult> = emptyList(),
    val error: String? = null,
)

data class SearchMangaResult(
    val title: String,
    val url: String,
    val thumbnailUrl: String? = null,
    val description: String? = null,
)

@Serializable
data class InstalledExtension(
    val name: String,
    val pkg: String,
    val repoId: String? = null,
    val repoName: String? = null,
    val repoIndexUrl: String? = null,
    val repoApkBaseUrl: String? = null,
    val apk: String,
    val version: String,
    val code: Long? = null,
    val nsfw: Boolean = false,
    val jarPath: String,
    val iconPath: String? = null,
    val sourceClasses: List<String>,
    val sources: List<InstalledSource>,
    val sourceLoadErrors: List<SourceLoadError> = emptyList(),
)

data class ExtensionUpdate(
    val name: String,
    val pkg: String,
    val repoId: String,
    val repoName: String,
    val installedVersion: String,
    val availableVersion: String,
    val installedCode: Long?,
    val availableCode: Long,
    val installedApk: String,
    val availableApk: String,
)

@Serializable
data class InstalledSource(val id: Long, val lang: String, val name: String)

data class CompatibilityResult(
    val name: String,
    val pkg: String,
    val version: String,
    val ok: Boolean,
    val sources: List<InstalledSource> = emptyList(),
    val sourceLoadErrors: List<SourceLoadError> = emptyList(),
    val errorType: String? = null,
    val errorMessage: String? = null,
    val missingSymbol: String? = null,
)

data class ProbeStage(val name: String, val ok: Boolean, val message: String) {
    companion object {
        fun failure(name: String, error: Throwable): ProbeStage {
            val detail = error.compatibilityDetail()
            return ProbeStage(name, false, "${detail.type}: ${detail.missingSymbol ?: detail.message}")
        }
    }
}

data class ProbeResult(
    val name: String,
    val pkg: String,
    val version: String,
    val sourceId: Long? = null,
    val sourceName: String? = null,
    val sourceLang: String? = null,
    val ok: Boolean,
    val stages: List<ProbeStage>,
    val mangaTitle: String? = null,
    val mangaUrl: String? = null,
    val chapterName: String? = null,
    val chapterUrl: String? = null,
    val resultCount: Int? = null,
    val chapterCount: Int? = null,
    val pageCount: Int? = null,
) {
    companion object {
        fun fromFailure(
            extension: KeiyoushiExtension,
            stages: List<ProbeStage>,
            source: InstalledSource? = null,
            mangaTitle: String? = null,
            mangaUrl: String? = null,
            resultCount: Int? = null,
            chapterCount: Int? = null,
        ): ProbeResult {
            return ProbeResult(
                name = extension.name.removePrefix("Tachiyomi: ").trim(),
                pkg = extension.pkg,
                version = extension.version,
                sourceId = source?.id,
                sourceName = source?.name,
                sourceLang = source?.lang,
                ok = false,
                stages = stages,
                mangaTitle = mangaTitle,
                mangaUrl = mangaUrl,
                resultCount = resultCount,
                chapterCount = chapterCount,
            )
        }
    }
}
