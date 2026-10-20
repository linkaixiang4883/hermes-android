package com.hermesagent.hermes_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
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

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.hermesagent.hermes_android/share"
    private val launchChannelName = "com.hermesagent.hermes_android/launch"
    private val downloadsChannelName = "com.hermesagent.hermes_android/downloads"
    private val notificationChannelId = "hermes_media_downloads"
    private val notificationPermissionRequest = 4310
    private val quickChatAction = "com.hermesagent.hermes_android.action.QUICK_CHAT"
    private val maxSharedItems = 10
    private val maxSharedBytes = 64L * 1024L * 1024L
    private var shareChannel: MethodChannel? = null
    private var launchChannel: MethodChannel? = null
    private var downloadsChannel: MethodChannel? = null
    private var initialShareIntent: Intent? = null
    private var initialLaunchAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        initialShareIntent = intent.takeIf(::isShareIntent)
        initialLaunchAction = launchActionFor(intent)
        super.onCreate(savedInstanceState)
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
                                val installIntent =
                                    if (saved != null && installAfterSave) buildInstallIntent(name, bytes) else null
                                runOnUiThread {
                                    if (installIntent != null) {
                                        runCatching { startActivity(installIntent) }
                                    }
                                    if (saved != null) postSavedNotification(name, installIntent)
                                    result.success(saved)
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /// Builds the system package-installer intent for an APK save. The bytes
    /// are copied into the app cache because the installer needs a URI this
    /// app can grant — a MediaStore row is not a installable source on every
    /// OEM build.
    private fun buildInstallIntent(filename: String, bytes: ByteArray): Intent? {
        return try {
            val dir = File(cacheDir, "install").apply { mkdirs() }
            val file = File(dir, filename)
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(this, "$packageName.downloads", file)
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } catch (e: Exception) {
            null
        }
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
    /// Returns the saved display name, or null when this release predates
    /// scoped storage — the caller then falls back to the share sheet.
    private fun saveToDownloads(filename: String, mimeType: String?, bytes: ByteArray): String? {
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
            filename
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
