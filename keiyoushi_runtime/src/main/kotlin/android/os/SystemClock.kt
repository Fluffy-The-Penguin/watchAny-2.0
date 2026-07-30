package android.os

object SystemClock {
    @JvmStatic
    fun elapsedRealtime(): Long = System.currentTimeMillis()

    @JvmStatic
    fun uptimeMillis(): Long = System.currentTimeMillis()

    @JvmStatic
    fun currentThreadTimeMillis(): Long = System.currentTimeMillis()
}
