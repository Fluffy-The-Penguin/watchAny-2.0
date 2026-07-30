package eu.kanade.tachiyomi.runtime

import eu.kanade.tachiyomi.runtime.loader.ExtensionManager
import eu.kanade.tachiyomi.runtime.server.ServerRoutes
import io.javalin.Javalin

fun main(args: Array<String>) {
    val port = if (args.size >= 2 && args[0] == "web") {
        args[1].toIntOrNull() ?: 4567
    } else {
        4567
    }

    println("[KeiyoushiRuntime] Starting Javalin HTTP server on port $port...")
    val app = Javalin.create { config ->
        config.showJavalinBanner = false
    }

    ServerRoutes.register(app)
    app.start("0.0.0.0", port)
    println("[KeiyoushiRuntime] Server running on http://127.0.0.1:$port")

    println("[KeiyoushiRuntime] Loading installed extensions...")
    try {
        ExtensionManager.loadAllInstalledExtensions()
        println("[KeiyoushiRuntime] Extension loading complete!")
    } catch (e: Exception) {
        println("[KeiyoushiRuntime] Error loading extensions: $e")
    }
}
