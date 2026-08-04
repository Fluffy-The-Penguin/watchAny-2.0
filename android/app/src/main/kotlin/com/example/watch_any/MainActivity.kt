package com.example.watch_any

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
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
                } else if (call.method == "installApk") {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file not found at path: $filePath", null)
                                return@setMethodCallHandler
                            }
                            
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                if (!packageManager.canRequestPackageInstalls()) {
                                    val settingsIntent = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                        data = Uri.parse("package:$packageName")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(settingsIntent)
                                    result.success(false)
                                    return@setMethodCallHandler
                                }
                            }

                            val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    file
                                )
                            } else {
                                Uri.fromFile(file)
                            }

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", "Failed to start installer intent: ${e.message}", e.toString())
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath argument is null", null)
                    }
                } else if (call.method == "uninstallApk") {
                    val pkgName = call.argument<String>("pkgName")
                    if (!pkgName.isNullOrBlank()) {
                        try {
                            val intent = Intent(Intent.ACTION_DELETE).apply {
                                data = Uri.parse("package:$pkgName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNINSTALL_FAILED", "Failed to start uninstall intent: ${e.message}", e.toString())
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "pkgName argument is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

    }
    private var webServer: LocalWebServer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val attrib = window.attributes
            attrib.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = attrib
        }
        
        try {
            runtime.PackageTools.injectDexAtStartup(applicationContext)
            // Register Application and Context in Injekt scope so dynamic extensions can access preferences
            Injekt.register(android.app.Application::class.java, application)
            Injekt.register(android.content.Context::class.java, applicationContext)
            
            // Register Json utility
            Injekt.register(Json::class.java, Json {
                ignoreUnknownKeys = true
                explicitNulls = false
                coerceInputValues = true
                isLenient = true
            })
            
            // Register Network helper and client
            val networkHelper = NetworkHelper()
            Injekt.register(NetworkHelper::class.java, networkHelper)
            Injekt.register(OkHttpClient::class.java, networkHelper.client)

            // Register PreferenceStore for Tachiyomi extensions
            val prefStore = tachiyomi.core.common.preference.AndroidPreferenceStore(applicationContext)
            Injekt.register(tachiyomi.core.common.preference.PreferenceStore::class.java, prefStore)
            // Start Manga extension server asynchronously in background thread so app startup is instant
            java.util.concurrent.Executors.newSingleThreadExecutor().execute {
                try {
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
