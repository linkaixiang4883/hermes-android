package com.hermesagent.hermes_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    /// A MediaStore row this app wrote, kept as both the display name the
    /// caller reports back and the uri whose row is deleted once the APK's
    /// install lands on a later launch.
    private data class SavedDownload(val filename: String, val uri: String)

    private val shareChannelName = "com.hermesagent.hermes_android/share"
    private val launchChannelName = "com.hermesagent.hermes_android/launch"
    private val downloadsChannelName = "com.hermesagent.hermes_android/downloads"
    private val keepAliveChannelName = "com.hermesagent.hermes_android/keep_alive"
    private val TAG = "HermesDownloads"
    private val prefsName = "hermes_downloads"
    private val installCleanupKey = "install_cleanup_v1"
    /// Age after which an uninstalled APK copy in cacheDir/install is noise.
    private val installCacheMaxAgeMs = 7L * 24L * 60L * 60L * 1000L
    private val notificationChannelId = "hermes_media_downloads"
    private val notificationPermissionRequest = 4310
    private val quickChatAction = "com.hermesagent.hermes_android.action.QUICK_CHAT"
    private val maxSharedItems = 10
    private val maxSharedBytes = 64L * 1024L * 1024L
    private var shareChannel: MethodChannel? = null
    private var launchChannel: MethodChannel? = null
    private var downloadsChannel: MethodChannel? = null
    private var keepAliveChannel: MethodChannel? = null
    private var initialShareIntent: Intent? = null
    private var initialLaunchAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        initialShareIntent = intent.takeIf(::isShareIntent)
        initialLaunchAction = launchActionFor(intent)
        super.onCreate(savedInstanceState)
        // An in-place APK install replaces this process, so the saved copy can
        // only be deleted on the first launch of the new version. Keeping the
        // accounting off the UI thread means a slow resolver never delays the
        // first frame, and every failure inside is swallowed to a log line.
        Thread({ reconcileInstallCleanup() }, "hermes-install-cleanup").start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        val pending = initialShareIntent
                        initialShareIntent = null
                        processShareIntent(pending) { payload -> result.success(payload) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLaunchAction" -> {
                        val pending = initialLaunchAction
                        initialLaunchAction = null
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        downloadsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val filename = call.argument<String>("filename")?.trim().orEmpty()
                        val mimeType = call.argument<String>("mimeType")
                        val installAfterSave = call.argument<Boolean>("installAfterSave") ?: false
                        if (bytes == null || filename.isEmpty()) {
                            result.success(null)
                        } else {
                            // Tens of MB may be written (media row + APK cache
                            // copy): keep it off the platform thread, then come
                            // back for the intent, the notification and the reply.
                            val name = filename.substringAfterLast('/')
                            Thread {
                                val saved = saveToDownloads(name, mimeType, bytes)
                                Log.i(TAG, "saveToDownloads filename=$name saved=${saved?.filename} mime=$mimeType")
                                var installIntent: Intent? = null
                                var installStatus = "none"
                                if (saved != null && installAfterSave) {
                                    val mayInstall = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                        packageManager.canRequestPackageInstalls()
                                    Log.i(TAG, "install requested; mayInstall=$mayInstall")
                                    installIntent = if (mayInstall) buildInstallIntent(name, bytes) else null
                                    installStatus = when {
                                        !mayInstall -> "permission"
                                        installIntent == null -> "failed"
                                        else -> "launched"
                                    }
                                }
                                runOnUiThread {
                                    if (installStatus == "launched" && installIntent != null) {
                                        try {
                                            startActivity(installIntent)
                                            // This process dies with the install, so
                                            // record what to delete before handing
                                            // over to the installer.
                                            rememberInstallCleanup(name, saved?.uri)
                                        } catch (e: Exception) {
                                            Log.w(TAG, "installer launch failed", e)
                                            installStatus = "failed"
                                        }
                                    } else if (installStatus == "permission") {
                                        openInstallPermissionSettings()
                                    }
                                    if (saved != null) postSavedNotification(saved.filename, installIntent)
                                    result.success(
                                        if (saved == null) null
                                        else mapOf("filename" to saved.filename, "install" to installStatus)
                                    )
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        keepAliveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keepAliveChannelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(startKeepAlive())
                    "stop" -> result.success(HermesConnectionService.stop(this@MainActivity))
                    else -> result.notImplemented()
                }
            }
        }
    }

    /// Starts the optional foreground service and reports whether Android
    /// accepted it. On 13+ the ongoing notification is only drawn when
    /// POST_NOTIFICATIONS is granted, but the service itself still runs, so a
    /// missing permission is logged and the start is reported as-is instead of
    /// failing the caller (the setting must not look broken because of it).
    private fun startKeepAlive(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.i(TAG, "keep-alive started without POST_NOTIFICATIONS; notification stays hidden")
        }
        val started = HermesConnectionService.start(this)
        Log.i(TAG, "keep-alive start requested started=$started")
        return started
    }

    /// Builds the system package-installer intent for an APK save. The bytes
    /// are copied into the app cache because the installer needs a URI this
    /// app can grant — a MediaStore row is not a installable source on every
    /// OEM build.
    private fun buildInstallIntent(filename: String, bytes: ByteArray): Intent? {
        return try {
            val file = installCacheFile(filename)
            file.parentFile?.mkdirs()
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(this, "$packageName.downloads", file)
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } catch (e: Exception) {
            Log.w(TAG, "buildInstallIntent failed for $filename", e)
            null
        }
    }

    /// The cache copy handed to the installer, and the path the cleanup pass
    /// deletes once the install lands.
    private fun installCacheFile(filename: String): File = File(File(cacheDir, "install"), filename)

    /// Records what to delete after the imminent install. Called right after
    /// the installer intent is handed off: the install replaces this process,
    /// so nothing here can wait for a result. A commit (not apply) keeps the
    /// record on disk even if the process is killed seconds later.
    private fun rememberInstallCleanup(filename: String, downloadsUri: String?) {
        try {
            val versionCode = currentVersionCode()
            if (versionCode <= 0L) {
                Log.w(TAG, "install cleanup skipped: version code unavailable")
                return
            }
            val payload = JSONObject().apply {
                put("versionCodeAtSave", versionCode)
                put("downloadsUri", downloadsUri.orEmpty())
                put("cachePath", installCacheFile(filename).absolutePath)
                put("filename", filename)
                put("savedAt", System.currentTimeMillis())
            }
            val committed = prefs().edit().putString(installCleanupKey, payload.toString()).commit()
            Log.i(
                TAG,
                "install cleanup armed filename=$filename versionCode=$versionCode " +
                    "uri=$downloadsUri committed=$committed",
            )
        } catch (e: Exception) {
            Log.w(TAG, "install cleanup could not be armed", e)
        }
    }

    /// The one-shot reconciliation of the last armed install. Runs off the UI
    /// thread at startup: an in-place APK install kills the old process, so
    /// the new version is the first chance to delete both copies. A bumped
    /// version code means the install landed; an unchanged one means the user
    /// cancelled or the install failed, so the saved APK stays available.
    private fun reconcileInstallCleanup() {
        try {
            val raw = prefs().getString(installCleanupKey, null) ?: return
            val state = runCatching { JSONObject(raw) }.getOrNull()
            if (state == null) {
                Log.w(TAG, "install cleanup state unreadable; dropping it")
                prefs().edit().remove(installCleanupKey).apply()
                return
            }
            val versionAtSave = state.optLong("versionCodeAtSave", -1L)
            val downloadsUri = state.optString("downloadsUri").takeIf { it.isNotEmpty() }
            val cachePath = state.optString("cachePath").takeIf { it.isNotEmpty() }
            val filename = state.optString("filename")
            val current = currentVersionCode()
            if (versionAtSave > 0L && current > versionAtSave) {
                if (downloadsUri != null) deleteDownloadsRow(downloadsUri)
                if (cachePath != null) {
                    val cacheFile = File(cachePath)
                    Log.i(TAG, "install cleanup: cache file ${cacheFile.name} deleted=${cacheFile.delete()}")
                }
                prefs().edit().remove(installCleanupKey).commit()
                Log.i(
                    TAG,
                    "install of $filename confirmed ($versionAtSave -> $current); " +
                        "saved APK removed",
                )
            } else {
                sweepStaleInstallCopies(keepPath = cachePath)
                Log.i(
                    TAG,
                    "install of $filename not confirmed (saved at $versionAtSave, now $current); " +
                        "keeping the saved APK",
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "install cleanup reconcile failed", e)
        }
    }

    /// Deletes the Downloads (MediaStore) row this app inserted. Only this
    /// app's own row is addressed, so no storage permission is involved; a
    /// failure (row already gone, OEM restriction) is logged and ignored.
    private fun deleteDownloadsRow(downloadsUri: String) {
        try {
            val deleted = contentResolver.delete(Uri.parse(downloadsUri), null, null)
            Log.i(TAG, "install cleanup: downloads row $downloadsUri deleted=$deleted")
        } catch (e: Exception) {
            Log.w(TAG, "install cleanup: deleting $downloadsUri failed", e)
        }
    }

    /// Keeps an unconfirmed install's APK for the retry, but stops old copies
    /// from accumulating in cacheDir/install forever. Files newer than the
    /// window — and the recorded copy itself — are left alone.
    private fun sweepStaleInstallCopies(keepPath: String?) {
        try {
            val cutoff = System.currentTimeMillis() - installCacheMaxAgeMs
            val dir = File(cacheDir, "install")
            dir.listFiles()?.forEach { file ->
                if (file.absolutePath == keepPath) return@forEach
                if (file.lastModified() > cutoff) return@forEach
                val deleted = runCatching { file.delete() }.getOrDefault(false)
                if (deleted) Log.i(TAG, "install cleanup: dropped stale copy ${file.name}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "install cleanup: stale sweep failed", e)
        }
    }

    private fun currentVersionCode(): Long = try {
        val info = packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    } catch (e: Exception) {
        Log.w(TAG, "package version unavailable", e)
        -1L
    }

    private fun prefs(): SharedPreferences = getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    /// Opens the system "install unknown apps" page for this app — the
    /// permission surface Android 8+ uses instead of a runtime dialog.
    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            Log.i(TAG, "opened install-permission settings")
        }.onFailure { Log.w(TAG, "install-permission settings failed", it) }
    }

    /// Posts the "saved" notification. For an APK both the tap and the
    /// 安装 action point at the system installer — Android launches it even
    /// when this app is not running. Older releases without the notification
    /// permission simply drop the post; the file is saved either way.
    private fun postSavedNotification(filename: String, installIntent: Intent?) {
        ensureDownloadChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            // Ask once; the post below is harmless without it and the next
            // save lands with the permission granted.
            runCatching {
                requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    notificationPermissionRequest,
                )
            }
        }
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return
        val installPending = installIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
        val contentIntent = installPending ?: PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(t("已保存到下载", "Saved to Downloads"))
            .setContentText(filename)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        if (installPending != null) {
            builder.addAction(
                android.R.drawable.stat_sys_download_done,
                t("安装", "Install"),
                installPending,
            )
        }
        runCatching {
            NotificationManagerCompat.from(this)
                .notify((System.currentTimeMillis() and 0xFFFFFF).toInt(), builder.build())
        }
    }

    private fun ensureDownloadChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(notificationChannelId) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                notificationChannelId,
                t("文件下载", "File downloads"),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun t(zh: String, en: String): String =
        if (Locale.getDefault().language.startsWith("zh")) zh else en

    /// Writes [bytes] into the system Downloads collection (MediaStore, API 29+).
    /// Returns the saved row, or null when this release predates scoped
    /// storage — the caller then falls back to the share sheet. The uri is kept
    /// because the cleanup pass deletes exactly this row after the APK installs.
    private fun saveToDownloads(filename: String, mimeType: String?, bytes: ByteArray): SavedDownload? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mimeType ?: "application/octet-stream")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        val stream = try {
            resolver.openOutputStream(uri)
        } catch (e: Exception) {
            null
        }
        if (stream == null) {
            runCatching { resolver.delete(uri, null, null) }
            return null
        }
        return try {
            stream.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            SavedDownload(filename, uri.toString())
        } catch (e: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchActionFor(intent)?.let { action ->
            launchChannel?.invokeMethod("launchAction", action)
            return
        }
        if (!isShareIntent(intent)) return
        processShareIntent(intent) { payload ->
            if (payload != null) shareChannel?.invokeMethod("sharePayload", payload)
        }
    }

    private fun launchActionFor(intent: Intent?): String? =
        if (intent?.action == quickChatAction) "quickChat" else null

    private fun isShareIntent(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE

    private fun processShareIntent(intent: Intent?, callback: (Map<String, Any?>?) -> Unit) {
        if (!isShareIntent(intent)) {
            callback(null)
            return
        }
        Thread {
            val payload = extractSharePayload(intent!!)
            runOnUiThread { callback(payload) }
        }.start()
    }

    private fun extractSharePayload(intent: Intent): Map<String, Any?>? {
        val text = extractSharedText(intent)
        val files = mutableListOf<Map<String, Any>>()
        var copiedBytes = 0L
        sharedUris(intent).take(maxSharedItems).forEachIndexed { index, uri ->
            val remaining = maxSharedBytes - copiedBytes
            if (remaining <= 0L) return@forEachIndexed
            copySharedUri(uri, index, intent.type, remaining)?.let { file ->
                files += file
                copiedBytes += file["byteLength"] as Long
            }
        }
        if (text == null && files.isEmpty()) return null
        return mapOf("text" to text, "files" to files)
    }

    private fun extractSharedText(intent: Intent): String? {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        return when {
            text.isEmpty() -> subject.ifEmpty { null }
            subject.isEmpty() || text.startsWith(subject) -> text
            else -> "$subject\n\n$text"
        }
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> {
        val streams = when (intent.action) {
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            Intent.ACTION_SEND ->
                listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            else -> emptyList()
        }.toMutableList()
        val clip = intent.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(streams::add)
            }
        }
        return streams.distinct()
    }

    private fun copySharedUri(
        uri: Uri,
        index: Int,
        fallbackType: String?,
        remainingBytes: Long,
    ): Map<String, Any>? {
        val mediaType = contentResolver.getType(uri)?.trim().orEmpty()
            .ifEmpty { fallbackType?.trim().orEmpty() }
            .ifEmpty { "application/octet-stream" }
        val displayName = queryDisplayName(uri)
            ?.let(::safeDisplayName)
            ?.takeIf(String::isNotEmpty)
            ?: "shared-${index + 1}"
        val directory = File(cacheDir, "shared_intake").apply { mkdirs() }
        val destination = File(directory, "${UUID.randomUUID()}-$displayName")
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            var total = 0L
            input.use { source ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > remainingBytes) {
                            throw IllegalArgumentException("Shared payload exceeds 64 MiB")
                        }
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            if (total <= 0L) {
                destination.delete()
                null
            } else {
                mapOf(
                    "path" to destination.absolutePath,
                    "name" to displayName,
                    "mediaType" to mediaType,
                    "byteLength" to total,
                )
            }
        } catch (_: Exception) {
            destination.delete()
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column < 0) null else cursor.getString(column)
        }
    } catch (_: Exception) {
        null
    }

    private fun safeDisplayName(value: String): String =
        value.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._() -]"), "_")
            .take(160)
}
