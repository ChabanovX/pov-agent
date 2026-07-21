package com.example.pov_agent

import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var recordedVideoFrameChannel: RecordedVideoFrameChannel? = null
    private var modelDiskCapacityChannel: ModelDiskCapacityChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        recordedVideoFrameChannel = RecordedVideoFrameChannel(
            context = applicationContext,
            messenger = messenger,
            assetLookup = { assetPath ->
                FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
            },
        )
        modelDiskCapacityChannel = ModelDiskCapacityChannel(
            context = applicationContext,
            messenger = messenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        recordedVideoFrameChannel?.dispose()
        recordedVideoFrameChannel = null
        modelDiskCapacityChannel?.dispose()
        modelDiskCapacityChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
