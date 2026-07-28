package eu.kanade.tachiyomi.source

import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import rx.Observable
import tachiyomi.core.common.util.lang.awaitSingle

interface CatalogueSource : Source {
    override val lang: String
    override val supportsLatest: Boolean

    @Suppress("DEPRECATION")
    override suspend fun getPopularManga(page: Int): MangasPage = fetchPopularManga(page).awaitSingle()

    @Suppress("DEPRECATION")
    override suspend fun getSearchManga(page: Int, query: String, filters: FilterList): MangasPage = fetchSearchManga(page, query, filters).awaitSingle()

    @Suppress("DEPRECATION")
    override suspend fun getLatestUpdates(page: Int): MangasPage = fetchLatestUpdates(page).awaitSingle()

    override fun getFilterList(): FilterList = FilterList()

    @Deprecated("Use getPopularManga instead")
    override fun fetchPopularManga(page: Int): Observable<MangasPage> = throw UnsupportedOperationException()

    @Deprecated("Use getSearchManga instead")
    override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> = throw UnsupportedOperationException()

    @Deprecated("Use getLatestUpdates instead")
    override fun fetchLatestUpdates(page: Int): Observable<MangasPage> = throw UnsupportedOperationException()
}
