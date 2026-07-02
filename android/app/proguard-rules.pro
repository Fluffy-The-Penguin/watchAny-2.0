# Proguard rules for watchAny Manga Extension Runtime

# Keep the entire Tachiyomi API packages so they are not obfuscated or optimized
-keep class eu.kanade.tachiyomi.** { *; }
-keep interface eu.kanade.tachiyomi.** { *; }

# Keep other compat runtime packages
-keep class runtime.** { *; }
-keep class xyz.anyplay.** { *; }
-keep class tachiyomi.** { *; }
-keep class uy.kohesive.injekt.** { *; }
-keep class rx.** { *; }
-keep class okhttp3.** { *; }
-keep class org.jsoup.** { *; }

# Ignore missing class warnings from OkHttp, JSoup, and GraalVM dependencies
-dontwarn com.oracle.svm.core.**
-dontwarn org.graalvm.nativeimage.**
-dontwarn org.jspecify.annotations.**
-dontwarn java.lang.Module

# Prevent optimization from declaring classes final
-dontoptimize
