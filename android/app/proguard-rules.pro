# Proguard rules for watchAny Manga Extension Runtime & Mihon Extensions

-dontobfuscate
-dontoptimize

# Keep all Tachiyomi & Mihon API packages
-keep class eu.kanade.** { *; }
-keep interface eu.kanade.** { *; }
-keep class tachiyomi.** { *; }
-keep interface tachiyomi.** { *; }
-keep class mihon.** { *; }
-keep interface mihon.** { *; }

# Keep runtime engine packages
-keep class runtime.** { *; }
-keep class xyz.anyplay.** { *; }
-keep class uy.kohesive.injekt.** { *; }

# Keep common dependencies used by Mihon/Tachiyomi extensions
-keep class androidx.preference.** { *; }
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class kotlinx.serialization.** { *; }
-keep class kotlin.time.** { *; }
-keep class okhttp3.** { *; }
-keepclassmembers class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class org.jsoup.** { *; }
-keep class rx.** { *; }
-keep class app.cash.quickjs.** { *; }
-keep class com.squareup.zstd.** { *; }

-keepclassmembers class * implements java.io.Serializable {
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Ignore warnings from optional dependencies
-dontwarn com.oracle.svm.core.**
-dontwarn org.graalvm.nativeimage.**
-dontwarn org.jspecify.annotations.**
-dontwarn java.lang.Module
-dontwarn sun.misc.**
