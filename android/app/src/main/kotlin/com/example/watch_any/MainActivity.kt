package com.example.watch_any

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import runtime.ExtensionRuntime
import runtime.LocalWebServer
import uy.kohesive.injekt.Injekt
import kotlinx.serialization.json.Json
import eu.kanade.tachiyomi.network.NetworkHelper
import okhttp3.OkHttpClient

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.watch_any/native_path")
            .setMethodCallHandler { call, result ->
                if (call.method == "getNativeLibraryDir") {
                    result.success(applicationInfo.nativeLibraryDir)
                } else {
                    result.notImplemented()
                }
            }
    }
    private var webServer: LocalWebServer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        try {
            // Register Application and Context in Injekt scope so dynamic extensions can access preferences
            Injekt.register(android.app.Application::class.java, application)
            Injekt.register(android.content.Context::class.java, applicationContext)
            
            // Register Json utility
            Injekt.register(Json::class.java, Json { ignoreUnknownKeys = true })
            
            // Register Network helper and client
            val networkHelper = NetworkHelper()
            Injekt.register(NetworkHelper::class.java, networkHelper)
            Injekt.register(OkHttpClient::class.java, networkHelper.client)
            // Read port from SharedPreferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val portLong = runCatching { prefs.getLong("flutter.manga_server_port", 4567L) }
                .getOrElse { 
                    runCatching { prefs.getInt("flutter.manga_server_port", 4567).toLong() }
                        .getOrDefault(4567L) 
                }
            val port = portLong.toInt()

            val rootPath = File(filesDir, "manga_runtime").toPath()
            val runtime = ExtensionRuntime(this, rootPath)
            
            webServer = LocalWebServer(this, runtime, port).apply {
                start()
            }
            android.util.Log.d("watchAny-MainActivity", "Manga extension server started successfully on port $port")
        } catch (e: Exception) {
            android.util.Log.e("watchAny-MainActivity", "Failed to start Manga extension server: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        try {
            webServer?.stop()
            webServer = null
            android.util.Log.d("watchAny-MainActivity", "Manga extension server stopped successfully")
        } catch (e: Exception) {
            android.util.Log.e("watchAny-MainActivity", "Error stopping Manga extension server: ${e.message}", e)
        }
        super.onDestroy()
    }
}
