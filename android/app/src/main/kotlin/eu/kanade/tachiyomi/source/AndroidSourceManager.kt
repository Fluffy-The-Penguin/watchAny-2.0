package eu.kanade.tachiyomi.source

import android.content.Context
import eu.kanade.tachiyomi.source.online.HttpSource
import java.util.concurrent.ConcurrentHashMap

/**
 * Mihon & Komikku source manager.
 * Holds active sources keyed by unique source ID.
 */
class AndroidSourceManager(private val context: Context) {

    private val sourcesMap = ConcurrentHashMap<Long, Source>()

    fun registerSources(sources: List<Source>) {
        sources.forEach { source ->
            sourcesMap[source.id] = source
        }
    }

    fun unregisterSources(sources: List<Source>) {
        sources.forEach { source ->
            sourcesMap.remove(source.id)
        }
    }

    fun get(sourceKey: Long): Source? {
        return sourcesMap[sourceKey]
    }

    fun getOrStub(sourceKey: Long): Source {
        return sourcesMap[sourceKey] ?: object : Source {
            override val id: Long = sourceKey
            override val name: String = "Stub Source ($sourceKey)"
            override val lang: String = "en"
        }
    }

    fun getAll(): List<Source> = sourcesMap.values.toList()

    fun getOnlineSources(): List<HttpSource> = sourcesMap.values.filterIsInstance<HttpSource>()

    fun getCatalogueSources(): List<CatalogueSource> = sourcesMap.values.filterIsInstance<CatalogueSource>()
}
