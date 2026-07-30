package eu.kanade.tachiyomi.source

import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SMangaUpdate
import rx.Observable
import tachiyomi.core.common.util.lang.awaitSingle
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Cache and lock helper to prevent race conditions and duplicate network requests
 * when details and chapter list are requested concurrently for the same manga.
 */
private object MangaUpdateCache {
    private val locks = ConcurrentHashMap<String, Mutex>()
    private val cache = ConcurrentHashMap<String, Pair<Long, SMangaUpdate>>()
    private const val CACHE_TTL_MS = 60_000L // 1 minute TTL

    suspend fun getOrFetch(
        manga: SManga,
        fetcher: suspend () -> SMangaUpdate
    ): SMangaUpdate {
        val key = manga.url
        val now = System.currentTimeMillis()

        // Check valid cache entry
        cache[key]?.let { (timestamp, result) ->
            if (now - timestamp < CACHE_TTL_MS) {
                return result
            }
        }

        // Lock per manga URL so concurrent requests await the first fetch
        val lock = locks.getOrPut(key) { Mutex() }
        return lock.withLock {
            // Re-check inside lock
            cache[key]?.let { (timestamp, result) ->
                if (now - timestamp < CACHE_TTL_MS) {
                    return@withLock result
                }
            }

            val result = fetcher()
            cache[key] = Pair(now, result)
            result
        }
    }
}

@Suppress("unused")
interface Source {

    val id: Long

    val name: String

    val lang: String
        get() = ""

    val supportsLatest: Boolean
        get() = false

    fun getFilterList(): FilterList = FilterList()

    // ─── Suspend API ─────────────────────────────────────────────────────────

    suspend fun getPopularManga(page: Int): MangasPage = fetchPopularManga(page).awaitSingle()

    suspend fun getLatestUpdates(page: Int): MangasPage = fetchLatestUpdates(page).awaitSingle()

    suspend fun getSearchManga(page: Int, query: String, filters: FilterList): MangasPage =
        fetchSearchManga(page, query, filters).awaitSingle()

    /**
     * Combined update method. Generated extensions (like Asura Scans) override this directly.
     * Default implementation delegates to fetchMangaDetails / fetchChapterList.
     */
    suspend fun getMangaUpdate(
        manga: SManga,
        chapters: List<SChapter>,
        fetchDetails: Boolean,
        fetchChapters: Boolean,
    ): SMangaUpdate {
        val updatedManga = if (fetchDetails) fetchMangaDetails(manga).awaitSingle() else manga
        val updatedChapters = if (fetchChapters) fetchChapterList(manga).awaitSingle() else chapters
        return SMangaUpdate(updatedManga, updatedChapters)
    }

    /**
     * Gets details for a manga using cached/mutex-guarded getMangaUpdate(true, true).
     */
    suspend fun getMangaDetails(manga: SManga): SManga {
        return MangaUpdateCache.getOrFetch(manga) {
            getMangaUpdate(manga, emptyList(), fetchDetails = true, fetchChapters = true)
        }.manga
    }

    /**
     * Gets chapters for a manga using cached/mutex-guarded getMangaUpdate(true, true).
     */
    suspend fun getChapterList(manga: SManga): List<SChapter> {
        return MangaUpdateCache.getOrFetch(manga) {
            getMangaUpdate(manga, emptyList(), fetchDetails = true, fetchChapters = true)
        }.chapters
    }

    suspend fun getPageList(chapter: SChapter): List<Page> = fetchPageList(chapter).awaitSingle()

    // ─── Observable API ──────────────────────────────────────────────────────

    fun fetchPopularManga(page: Int): Observable<MangasPage> = throw UnsupportedOperationException()

    fun fetchLatestUpdates(page: Int): Observable<MangasPage> = throw UnsupportedOperationException()

    fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> =
        throw UnsupportedOperationException()

    fun fetchMangaDetails(manga: SManga): Observable<SManga> = throw UnsupportedOperationException()

    fun fetchChapterList(manga: SManga): Observable<List<SChapter>> = throw UnsupportedOperationException()

    fun fetchPageList(chapter: SChapter): Observable<List<Page>> = throw UnsupportedOperationException()
}
