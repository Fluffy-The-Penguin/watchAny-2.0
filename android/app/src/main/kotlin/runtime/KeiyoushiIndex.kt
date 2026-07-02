package runtime

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

const val DEFAULT_REPO_INDEX_URL = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"
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
    val apkUrl: String get() = DEFAULT_REPO_APK_BASE_URL + apk
}

@Serializable
data class KeiyoushiSource(
    val id: Long,
    val lang: String,
    val name: String,
    @SerialName("baseUrl") val baseUrl: String,
)

class KeiyoushiIndex(private val client: OkHttpClient = OkHttpClient()) {
    private val json = Json { ignoreUnknownKeys = true }

    fun fetch(indexUrl: String = DEFAULT_REPO_INDEX_URL): List<KeiyoushiExtension> {
        val request = Request.Builder().url(indexUrl).header("Accept", "application/json").build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "Keiyoushi index failed: ${response.code}" }
            return json.decodeFromString<List<KeiyoushiExtension>>(response.body.string())
        }
    }
}
