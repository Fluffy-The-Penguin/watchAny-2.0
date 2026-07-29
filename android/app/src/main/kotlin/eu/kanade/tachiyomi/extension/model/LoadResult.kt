package eu.kanade.tachiyomi.extension.model

import eu.kanade.tachiyomi.source.Source

sealed class LoadResult {
    data class Success(val extension: Extension.Installed) : LoadResult()
    data class Untrusted(val extension: Extension.Untrusted) : LoadResult()
    object Error : LoadResult()
}

sealed class Extension {
    abstract val name: String
    abstract val pkgName: String
    abstract val versionName: String
    abstract val versionCode: Long
    abstract val libVersion: Double
    abstract val lang: String
    abstract val isNsfw: Boolean

    data class Installed(
        override val name: String,
        override val pkgName: String,
        override val versionName: String,
        override val versionCode: Long,
        override val libVersion: Double,
        override val lang: String,
        override val isNsfw: Boolean,
        val pkgFactory: String?,
        val sources: List<Source>,
        val iconUrl: String? = null,
        val isShared: Boolean = false,
        val hasUpdate: Boolean = false,
        val isObsolete: Boolean = false,
        val isUnofficial: Boolean = false,
        val apkPath: String? = null,
    ) : Extension()

    data class Available(
        override val name: String,
        override val pkgName: String,
        override val versionName: String,
        override val versionCode: Long,
        override val libVersion: Double,
        override val lang: String,
        override val isNsfw: Boolean,
        val apkName: String,
        val iconUrl: String,
        val sources: List<AvailableSource>,
    ) : Extension() {
        data class AvailableSource(
            val id: Long,
            val name: String,
            val lang: String,
            val baseUrl: String,
        )
    }

    data class Untrusted(
        override val name: String,
        override val pkgName: String,
        override val versionName: String,
        override val versionCode: Long,
        override val libVersion: Double,
        val signatureHash: String,
        override val lang: String = "",
        override val isNsfw: Boolean = false,
    ) : Extension()
}
