package com.devpark.bowling_diary

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class YuvConverter {
    companion object {
        const val CHANNEL = "bowling_diary/yuv_converter"

        fun register(engine: FlutterEngine) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "convert" -> {
                            try {
                                val args = call.arguments as Map<String, Any>
                                val width = args["width"] as Int
                                val height = args["height"] as Int
                                val yPlane = args["yPlane"] as ByteArray
                                val uPlane = args["uPlane"] as ByteArray
                                val vPlane = args["vPlane"] as ByteArray
                                val yRowStride = args["yRowStride"] as Int
                                val uvRowStride = args["uvRowStride"] as Int
                                val uvPixelStride = args["uvPixelStride"] as Int

                                val rgba = convertYuvToRgba(
                                    width, height,
                                    yPlane, uPlane, vPlane,
                                    yRowStride, uvRowStride, uvPixelStride,
                                )
                                result.success(mapOf("rgba" to rgba))
                            } catch (e: Exception) {
                                result.error("CONVERT_FAIL", e.message, null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
        }

        // YUV420 → RGBA8888 변환. 카메라 시점 회전 처리는 호출자 책임.
        private fun convertYuvToRgba(
            width: Int, height: Int,
            y: ByteArray, u: ByteArray, v: ByteArray,
            yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        ): ByteArray {
            val rgba = ByteArray(width * height * 4)
            for (j in 0 until height) {
                for (i in 0 until width) {
                    val yIdx = j * yRowStride + i
                    val uvIdx = (j / 2) * uvRowStride + (i / 2) * uvPixelStride
                    val Y = (y[yIdx].toInt() and 0xFF)
                    val U = (u[uvIdx].toInt() and 0xFF) - 128
                    val V = (v[uvIdx].toInt() and 0xFF) - 128

                    val r = (Y + 1.402 * V).toInt().coerceIn(0, 255)
                    val g = (Y - 0.344 * U - 0.714 * V).toInt().coerceIn(0, 255)
                    val b = (Y + 1.772 * U).toInt().coerceIn(0, 255)

                    val out = (j * width + i) * 4
                    rgba[out]     = r.toByte()
                    rgba[out + 1] = g.toByte()
                    rgba[out + 2] = b.toByte()
                    rgba[out + 3] = 0xFF.toByte()
                }
            }
            return rgba
        }
    }
}
