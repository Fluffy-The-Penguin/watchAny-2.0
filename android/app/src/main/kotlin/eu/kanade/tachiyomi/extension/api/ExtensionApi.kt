package eu.kanade.tachiyomi.extension.api

import eu.kanade.tachiyomi.extension.model.Extension
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Mihon Extension API.
 * Fetches available extensions from external repository indexes (e.g. Keiyoushi).
 */
class ExtensionApi(
    private val client: OkHttpClient = OkHttpClient(),
    private val json: Json = Json { ignoreUnknownKeys = true }
) {

    suspend fun fetchExtensions(indexUrl: String): List<Extension.Available> {
        val request = Request.Builder().url(indexUrl).build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Failed to fetch extension repo HTTP ${response.code}")
            val body = response.body.string()
            val rawList = json.decodeFromString<List<KeiyoushiExtensionItem>>(body)
            val apkBaseUrl = indexUrl.substringBeforeLast('/', missingDelimiterValue = indexUrl.trimEnd('/')).trimEnd('/') + "/apk/"

            return rawList.map { item ->
                Extension.Available(
                    name = item.name.removePrefix("Tachiyomi: ").removePrefix("Keiyoushi: ").trim(),
                    pkgName = item.pkg,
                    versionName = item.version,
                    versionCode = item.code.toLong(),
                    libVersion = 1.4,
                    lang = item.lang,
                    isNsfw = item.nsfw == 1,
                    apkName = item.apk,
                    iconUrl = apkBaseUrl + item.apk.replace(".apk", ".png"),
                    sources = item.sources.map { src ->
                        Extension.Available.AvailableSource(
                            id = src.id.toLongOrNull() ?: 0L,
                            name = src.name,
                            lang = src.lang,
                            baseUrl = src.baseUrl
                        )
                    }
                )
            }
        }
    }

    @Serializable
    private data class KeiyoushiExtensionItem(
        val name: String,
        val pkg: String,
        val apk: String,
        val lang: String,
        val code: Int,
        val version: String,
        val nsfw: Int = 0,
        val sources: List<KeiyoushiSourceItem> = emptyList()
    )

    @Serializable
    private data class KeiyoushiSourceItem(
        val name: String,
        val lang: String,
        val id: String,
        val baseUrl: String
    )
}
