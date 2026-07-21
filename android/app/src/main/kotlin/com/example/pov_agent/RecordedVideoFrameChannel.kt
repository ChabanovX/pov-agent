package com.example.pov_agent

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import kotlin.math.roundToLong

private const val RECORDED_VIDEO_CHANNEL_NAME = "pov_agent/recorded_video"
private const val FALLBACK_FRAME_RATE = 5.0

/**
 * Pull-based decoder for the bundled recorded video.
 *
 * Retriever state is confined to one executor. Dart requests another frame
 * only after YOLO finishes the previous one, so decoded frames are never
 * buffered across the platform boundary.
 */
class RecordedVideoFrameChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val assetLookup: (String) -> String,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, RECORDED_VIDEO_CHANNEL_NAME)
    private val decodeExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var disposed = false
    private var retriever: MediaMetadataRetriever? = null
    private var frameCount = 0
    private var frameRate = FALLBACK_FRAME_RATE
    private var frameNumber = 0L

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                val assetPath = call.argument<String>("assetPath")
                if (assetPath.isNullOrBlank()) {
                    result.error(
                        "VIDEO_INVALID_ARGUMENTS",
                        "open requires a non-empty assetPath.",
                        null,
                    )
                    return
                }
                perform(result) { open(assetPath) }
            }
            "nextFrame" -> perform(result, ::nextFrame)
            "close" -> perform(result) {
                closeReader()
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun perform(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        if (disposed) {
            result.error(
                "VIDEO_READER_UNAVAILABLE",
                "The recorded video decoder has already been released.",
                null,
            )
            return
        }
        decodeExecutor.execute {
            try {
                val value = operation()
                postResult { result.success(value) }
            } catch (failure: RecordedVideoChannelFailure) {
                postResult { result.error(failure.code, failure.message, null) }
            } catch (error: Exception) {
                postResult {
                    result.error(
                        "VIDEO_READER_FAILED",
                        error.message,
                        null,
                    )
                }
            }
        }
    }

    private fun postResult(callback: () -> Unit) {
        mainHandler.post {
            if (!disposed) callback()
        }
    }

    private fun open(assetPath: String): Map<String, Any> {
        closeReader()
        try {
            val assetFile = copyFlutterAsset(assetPath)
            val nextRetriever = MediaMetadataRetriever()
            nextRetriever.setDataSource(assetFile.absolutePath)
            retriever = nextRetriever

            val rawWidth = nextRetriever.requirePositiveMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
                "width",
            )
            val rawHeight = nextRetriever.requirePositiveMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
                "height",
            )
            val rotation = nextRetriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
            )?.toIntOrNull() ?: 0
            val durationMilliseconds = nextRetriever.requirePositiveMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
                "duration",
            )
            val durationMicroseconds = durationMilliseconds.toLong() * 1_000L
            val declaredFrameCount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                nextRetriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT,
                )?.toIntOrNull()
            } else {
                null
            }
            val declaredFrameRate = nextRetriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE,
            )?.toDoubleOrNull()

            frameRate = when {
                declaredFrameRate != null && declaredFrameRate > 0 -> declaredFrameRate
                declaredFrameCount != null && declaredFrameCount > 0 ->
                    declaredFrameCount * 1_000_000.0 / durationMicroseconds
                else -> FALLBACK_FRAME_RATE
            }
            frameCount = declaredFrameCount
                ?.takeIf { it > 0 }
                ?: (durationMicroseconds * frameRate / 1_000_000.0)
                    .roundToInt()
                    .coerceAtLeast(1)
            frameNumber = 0

            val swapsDimensions = rotation == 90 || rotation == 270
            return mapOf(
                "width" to if (swapsDimensions) rawHeight else rawWidth,
                "height" to if (swapsDimensions) rawWidth else rawHeight,
                "durationMicroseconds" to durationMicroseconds,
            )
        } catch (error: Exception) {
            closeReader()
            throw error
        }
    }

    private fun copyFlutterAsset(assetPath: String): File {
        val lookupKey = assetLookup(assetPath)
        val cacheDirectory = File(context.cacheDir, "recorded_video")
        if (!cacheDirectory.exists() && !cacheDirectory.mkdirs()) {
            throw RecordedVideoChannelFailure(
                "VIDEO_READER_FAILED",
                "The recorded-video cache directory could not be created.",
            )
        }
        val safeFilename = File(assetPath).name.replace(
            Regex("[^A-Za-z0-9._-]"),
            "_",
        )
        val targetFile = File(cacheDirectory, "${assetPath.hashCode()}-$safeFilename")
        try {
            context.assets.open(lookupKey).use { input ->
                targetFile.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (error: FileNotFoundException) {
            throw RecordedVideoChannelFailure(
                "VIDEO_ASSET_NOT_FOUND",
                "Bundled video asset was not found: $assetPath",
            )
        }
        return targetFile
    }

    private fun nextFrame(): Map<String, Any> {
        val activeRetriever = retriever ?: throw RecordedVideoChannelFailure(
            "VIDEO_READER_FAILED",
            "The recorded video must be opened before requesting frames.",
        )
        if (frameCount <= 0 || frameRate <= 0) {
            throw RecordedVideoChannelFailure(
                "VIDEO_NO_TRACK",
                "The video track reports invalid frame metadata.",
            )
        }

        val frameIndex = (frameNumber % frameCount).toInt()
        val presentationTimeMicroseconds =
            (frameIndex * 1_000_000.0 / frameRate).roundToLong()
        val bitmap = frameAtIndex(activeRetriever, frameIndex)
            ?: activeRetriever.getFrameAtTime(
                presentationTimeMicroseconds,
                MediaMetadataRetriever.OPTION_CLOSEST,
            )
            ?: throw RecordedVideoChannelFailure(
                "VIDEO_EMPTY",
                "The recorded video produced no decodable frame.",
            )
        val bytes = encodeJpeg(bitmap)
        frameNumber += 1
        return mapOf(
            "bytes" to bytes,
            "frameNumber" to frameNumber,
            "presentationTimeMicroseconds" to presentationTimeMicroseconds,
        )
    }

    private fun frameAtIndex(
        activeRetriever: MediaMetadataRetriever,
        frameIndex: Int,
    ): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return try {
            activeRetriever.getFrameAtIndex(frameIndex)
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun encodeJpeg(bitmap: Bitmap): ByteArray {
        try {
            return ByteArrayOutputStream().use { output ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)) {
                    throw RecordedVideoChannelFailure(
                        "VIDEO_FRAME_DECODE_FAILED",
                        "A decoded video frame could not be encoded as JPEG.",
                    )
                }
                output.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun MediaMetadataRetriever.requirePositiveMetadata(
        key: Int,
        label: String,
    ): Int {
        val value = extractMetadata(key)?.toIntOrNull()
        if (value != null && value > 0) return value
        throw RecordedVideoChannelFailure(
            "VIDEO_NO_TRACK",
            "The video track reports invalid $label metadata.",
        )
    }

    private fun closeReader() {
        try {
            retriever?.release()
        } finally {
            retriever = null
            frameCount = 0
            frameRate = FALLBACK_FRAME_RATE
            frameNumber = 0
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        decodeExecutor.execute(::closeReader)
        decodeExecutor.shutdown()
    }
}

private class RecordedVideoChannelFailure(
    val code: String,
    override val message: String,
) : Exception(message)
