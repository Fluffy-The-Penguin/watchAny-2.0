package eu.kanade.tachiyomi.source.online

import eu.kanade.tachiyomi.network.NetworkHelper
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
import java.util.concurrent.CompletableFuture
import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

abstract class HttpSource : CatalogueSource {
    abstract val baseUrl: String
    override val lang: String get() = "en"
    override val supportsLatest: Boolean get() = true

    open val network: NetworkHelper = NetworkHelper()
    open val client: OkHttpClient get() = network.client

    open fun headersBuilder(): Headers.Builder = Headers.Builder()
        .add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

    open val headers: Headers by lazy { headersBuilder().build() }

    open fun popularMangaRequest(page: Int): Request = throw UnsupportedOperationException("Not implemented")
    open fun popularMangaParse(response: Response): MangasPage = throw UnsupportedOperationException("Not implemented")

    open fun latestUpdatesRequest(page: Int): Request = throw UnsupportedOperationException("Not implemented")
    open fun latestUpdatesParse(response: Response): MangasPage = throw UnsupportedOperationException("Not implemented")

    open fun searchMangaRequest(page: Int, query: String, filters: FilterList): Request = throw UnsupportedOperationException("Not implemented")
    open fun searchMangaParse(response: Response): MangasPage = throw UnsupportedOperationException("Not implemented")

    open fun mangaDetailsParse(response: Response): SManga = throw UnsupportedOperationException("Not implemented")
    open fun chapterListParse(response: Response): List<SChapter> = throw UnsupportedOperationException("Not implemented")
    open fun pageListParse(response: Response): List<Page> = throw UnsupportedOperationException("Not implemented")

    private fun <T> invokeSuspendMethod(methodName: String, vararg args: Any?): T? {
        val method = javaClass.methods.firstOrNull { it.name == methodName && it.parameterTypes.size == args.size + 1 }
            ?: return null

        val future = CompletableFuture<T>()
        val continuation = object : Continuation<T> {
            override val context: CoroutineContext = EmptyCoroutineContext
            override fun resumeWith(result: Result<T>) {
                if (result.isSuccess) {
                    future.complete(result.getOrNull())
                } else {
                    future.completeExceptionally(result.exceptionOrNull())
                }
            }
        }

        val fullArgs = arrayOf(*args, continuation)
        val res = method.invoke(this, *fullArgs)
        if (res != kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED) {
            @Suppress("UNCHECKED_CAST")
            return res as T
        }
        return future.get()
    }

    override fun fetchPopularManga(page: Int): Observable<MangasPage> {
        return Observable.fromCallable {
            try {
                val suspendRes = invokeSuspendMethod<MangasPage>("getPopularManga", page)
                if (suspendRes != null) return@fromCallable suspendRes
            } catch (e: Exception) {
                val cause = e.cause ?: e
                if (cause !is UnsupportedOperationException && cause !is NoSuchMethodException) {
                    throw cause
                }
            }

            val response = client.newCall(popularMangaRequest(page)).execute()
            popularMangaParse(response)
        }
    }

    override fun fetchLatestUpdates(page: Int): Observable<MangasPage> {
        return Observable.fromCallable {
            try {
                val suspendRes = invokeSuspendMethod<MangasPage>("getLatestUpdates", page)
                if (suspendRes != null) return@fromCallable suspendRes
            } catch (e: Exception) {
                val cause = e.cause ?: e
                if (cause !is UnsupportedOperationException && cause !is NoSuchMethodException) {
                    throw cause
                }
            }

            val response = client.newCall(latestUpdatesRequest(page)).execute()
            latestUpdatesParse(response)
        }
    }

    override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> {
        return Observable.fromCallable {
            try {
                val suspendRes = invokeSuspendMethod<MangasPage>("getSearchManga", page, query, filters)
                if (suspendRes != null) return@fromCallable suspendRes
            } catch (e: Exception) {
                val cause = e.cause ?: e
                if (cause !is UnsupportedOperationException && cause !is NoSuchMethodException) {
                    throw cause
                }
            }

            val response = client.newCall(searchMangaRequest(page, query, filters)).execute()
            searchMangaParse(response)
        }
    }

    override fun fetchMangaDetails(manga: SManga): Observable<SManga> {
        return Observable.fromCallable {
            try {
                val suspendRes = invokeSuspendMethod<SManga>("getMangaDetails", manga)
                if (suspendRes != null) return@fromCallable suspendRes
            } catch (e: Exception) {
                val cause = e.cause ?: e
                if (cause !is UnsupportedOperationException && cause !is NoSuchMethodException) {
                    throw cause
                }
            }

            val req = Request.Builder().url(baseUrl + manga.url).headers(headers).build()
            val response = client.newCall(req).execute()
            mangaDetailsParse(response)
        }
    }

    override fun fetchChapterList(manga: SManga): Observable<List<SChapter>> {
        return Observable.fromCallable {
            try {
                val suspendRes = invokeSuspendMethod<List<SChapter>>("getChapterList", manga)
                if (suspendRes != null) return@fromCallable suspendRes
            } catch (e: Exception) {
                val cause = e.cause ?: e
                if (cause !is UnsupportedOperationException && cause !is NoSuchMethodException) {
                    throw cause
                }
            }

            val req = Request.Builder().url(baseUrl + manga.url).headers(headers).build()
            val response = client.newCall(req).execute()
            chapterListParse(response)
        }
    }

    override fun fetchPageList(chapter: SChapter): Observable<List<Page>> {
        return Observable.fromCallable {
            try {
                val suspendRes = invokeSuspendMethod<List<Page>>("getPageList", chapter)
                if (suspendRes != null) return@fromCallable suspendRes
            } catch (e: Exception) {
                val cause = e.cause ?: e
                if (cause !is UnsupportedOperationException && cause !is NoSuchMethodException) {
                    throw cause
                }
            }

            val req = Request.Builder().url(baseUrl + chapter.url).headers(headers).build()
            val response = client.newCall(req).execute()
            pageListParse(response)
        }
    }

    open fun setUrlWithoutDomain(manga: SManga, url: String) {
        manga.setUrlWithoutDomain(url)
    }

    override fun getFilterList(): FilterList = FilterList()
}

fun SManga.setUrlWithoutDomain(url: String) {
    this.url = if (url.startsWith("http://") || url.startsWith("https://")) {
        "/" + url.substringAfter("//").substringAfter("/")
    } else if (url.startsWith("/")) {
        url
    } else {
        "/$url"
    }
}
