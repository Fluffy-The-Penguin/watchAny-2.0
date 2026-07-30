package runtime

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient
import okhttp3.Request

const val DEFAULT_REPO_INDEX_URL = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json"
const val DEFAULT_REPO_APK_BASE_URL = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/"

@Serializable
data class KeiyoushiExtension(
    val name: String,
    val pkg: String,
    val apk: String,
    val lang: String,
    val code: Long,
    val version: String,
    val nsfw: Int,
    val sources: List<KeiyoushiSource> = emptyList(),
) {
    val apkUrl: String get() = if (apk.startsWith("http://") || apk.startsWith("https://")) apk else DEFAULT_REPO_APK_BASE_URL + apk
    val iconUrl: String get() = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/icon/$pkg.png"
}

@Serializable
data class KeiyoushiSource(
    val id: Long,
    val lang: String,
    val name: String,
    @SerialName("baseUrl") val baseUrl: String = "",
)

@Serializable
private data class KeiyoushiV2Resources(
    val apkUrl: String? = null,
    val iconUrl: String? = null,
    val jarUrl: String? = null,
)

@Serializable
private data class KeiyoushiV2Source(
    val id: String,
    val name: String,
    val language: String? = null,
    val homeUrl: String? = null,
)

@Serializable
private data class KeiyoushiV2Item(
    val name: String,
    val packageName: String,
    val versionName: String,
    val versionCode: String? = null,
    val contentWarning: String? = null,
    val resources: KeiyoushiV2Resources? = null,
    val sources: List<KeiyoushiV2Source> = emptyList(),
)

class KeiyoushiIndex(private val client: OkHttpClient = OkHttpClient()) {
    private val json = Json { ignoreUnknownKeys = true }

    fun fetch(indexUrl: String = DEFAULT_REPO_INDEX_URL): List<KeiyoushiExtension> {
        val targetUrl = when {
            indexUrl.endsWith("index.min.json", ignoreCase = true) -> indexUrl.replace("index.min.json", "index.json", ignoreCase = true)
            else -> indexUrl
        }

        return try {
            fetchInternal(targetUrl)
        } catch (e: Throwable) {
            if (targetUrl != indexUrl) {
                fetchInternal(indexUrl)
            } else {
                throw e
            }
        }
    }

    private fun fetchInternal(url: String): List<KeiyoushiExtension> {
        val request = Request.Builder().url(url).header("Accept", "application/json").build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "Keiyoushi index failed ${response.code}: $url" }
            val body = response.body.string()
            val element = json.parseToJsonElement(body)

            val array = extractExtensionArray(element) ?: return emptyList()

            if (array.firstOrNull()?.jsonObject?.containsKey("packageName") == true) {
                val v2Items = json.decodeFromJsonElement<List<KeiyoushiV2Item>>(array)
                return v2Items.map { item ->
                    val apk = item.resources?.apkUrl ?: "${item.packageName}.apk"
                    val lang = item.sources.firstOrNull()?.language ?: "en"
                    val code = item.versionCode?.toLongOrNull() ?: 1L
                    val isNsfw = if (item.contentWarning?.contains("NSFW", true) == true) 1 else 0

                    KeiyoushiExtension(
                        name = item.name,
                        pkg = item.packageName,
                        apk = apk,
                        lang = lang,
                        code = code,
                        version = item.versionName,
                        nsfw = isNsfw,
                        sources = item.sources.map { s ->
                            KeiyoushiSource(
                                id = s.id.toLongOrNull() ?: s.id.hashCode().toLong(),
                                lang = s.language ?: lang,
                                name = s.name,
                                baseUrl = s.homeUrl ?: "",
                            )
                        }
                    )
                }
            } else {
                return json.decodeFromJsonElement<List<KeiyoushiExtension>>(array)
            }
        }
    }

    private fun extractExtensionArray(element: JsonElement): JsonArray? {
        if (element is JsonArray) return element
        if (element is JsonObject) {
            val extList = element["extensionList"]
            if (extList is JsonArray) return extList
            if (extList is JsonObject) {
                val exts = extList["extensions"]
                if (exts is JsonArray) return exts
            }
            val exts = element["extensions"]
            if (exts is JsonArray) return exts
            if (exts is JsonObject) {
                val arr = exts["extensions"]
                if (arr is JsonArray) return arr
            }
            val data = element["data"]
            if (data is JsonArray) return data
        }
        return null
    }
}
