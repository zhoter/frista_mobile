package com.faskes.frista.frista_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.faskes.frista.frista_mobile/dlib"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val success = DlibBridge.init(applicationContext)
                        withContext(Dispatchers.Main) {
                            result.success(success)
                        }
                    }
                }
                "computeDescriptor" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val left = call.argument<Int>("left") ?: 0
                    val top = call.argument<Int>("top") ?: 0
                    val right = call.argument<Int>("right") ?: 0
                    val bottom = call.argument<Int>("bottom") ?: 0

                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Bytes cannot be null", null)
                        return@setMethodCallHandler
                    }

                    CoroutineScope(Dispatchers.Default).launch {
                        val descriptor = DlibBridge.computeDescriptorFromBytes(bytes, left, top, right, bottom)
                        withContext(Dispatchers.Main) {
                            if (descriptor != null) {
                                val list = descriptor.map { it.toDouble() }
                                result.success(list)
                            } else {
                                result.error("EXTRACTION_FAILED", "Could not extract face descriptor", null)
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
