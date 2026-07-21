package com.example.pov_agent

import android.content.Context
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val MODEL_STORAGE_CHANNEL_NAME = "pov_agent/model_storage"

/** Resolves no-backup model storage and reports its filesystem capacity. */
class ModelDiskCapacityChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, MODEL_STORAGE_CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resolveDirectory" -> resolveDirectory(result)
            "availableBytes" -> reportAvailableBytes(call, result)
            else -> result.notImplemented()
        }
    }

    private fun resolveDirectory(result: MethodChannel.Result) {
        val directory = File(context.noBackupFilesDir, "models")
        if ((!directory.exists() && !directory.mkdirs()) || !directory.isDirectory) {
            result.error(
                "MODEL_STORAGE_DIRECTORY_FAILED",
                "The no-backup model directory could not be created.",
                null,
            )
            return
        }
        result.success(directory.absolutePath)
    }

    private fun reportAvailableBytes(call: MethodCall, result: MethodChannel.Result) {
        val directoryPath = call.argument<String>("directoryPath")
        if (directoryPath.isNullOrBlank()) {
            result.error(
                "MODEL_STORAGE_INVALID_ARGUMENTS",
                "availableBytes requires a non-empty directoryPath.",
                null,
            )
            return
        }

        try {
            val directory = File(directoryPath)
            if (!directory.isDirectory) {
                result.error(
                    "MODEL_STORAGE_LOOKUP_FAILED",
                    "The model cache directory does not exist.",
                    null,
                )
                return
            }
            val availableBytes = StatFs(directory.absolutePath).availableBytes
            if (availableBytes < 0) {
                result.error(
                    "MODEL_STORAGE_INVALID_RESPONSE",
                    "The cache volume did not report a valid free byte count.",
                    null,
                )
                return
            }
            result.success(availableBytes)
        } catch (error: RuntimeException) {
            result.error(
                "MODEL_STORAGE_LOOKUP_FAILED",
                error.message,
                null,
            )
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
