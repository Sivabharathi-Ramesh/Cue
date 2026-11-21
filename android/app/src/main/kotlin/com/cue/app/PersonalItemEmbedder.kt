package com.cue.app

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt
import org.tensorflow.lite.Interpreter

/** Extracts features from the requested camera regions on the image worker. */
internal class PersonalItemEmbedder(assets: AssetManager) : AutoCloseable {
    companion object {
        const val FORMAT = "mobilenet-v3-small-075-v1"
        private const val SIDE = 224
        private const val FEATURES = 1024
    }

    // MediaPipe's MobileNetV3 image embedder uses RGB floats in [0, 1].
    private val model = assets.open("cue_mobilenet_v3_small.tflite").use { stream ->
        val data = stream.readBytes()
        ByteBuffer.allocateDirect(data.size).order(ByteOrder.nativeOrder()).apply {
            put(data)
            rewind()
        }
    }
    private val interpreter = Interpreter(model, Interpreter.Options().setNumThreads(2))
    private val input = ByteBuffer.allocateDirect(SIDE * SIDE * 3 * Float.SIZE_BYTES)
        .order(ByteOrder.nativeOrder())
    private val pixels = IntArray(SIDE * SIDE)

    fun describe(jpeg: ByteArray, regions: List<List<Double>>): List<FloatArray> {
        val image = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
            ?: throw IllegalArgumentException("Could not decode the camera frame")
        try {
            return regions.map { describeRegion(image, it) }
        } finally {
            image.recycle()
        }
    }

    private fun describeRegion(image: Bitmap, region: List<Double>): FloatArray {
        require(region.size == 4 && region.all { it.isFinite() && it in 0.0..1.0 })
        val left = (region[0] * image.width).roundToInt()
        val top = (region[1] * image.height).roundToInt()
        val right = (region[2] * image.width).roundToInt()
        val bottom = (region[3] * image.height).roundToInt()
        val crop = Bitmap.createBitmap(image, left, top, right - left, bottom - top)
        try {
            val scaled = Bitmap.createScaledBitmap(crop, SIDE, SIDE, true)
            try {
                scaled.getPixels(pixels, 0, SIDE, 0, 0, SIDE, SIDE)
                input.clear()
                for (pixel in pixels) {
                    input.putFloat(((pixel shr 16) and 255) / 255f)
                    input.putFloat(((pixel shr 8) and 255) / 255f)
                    input.putFloat((pixel and 255) / 255f)
                }
                input.rewind()
                val output = Array(1) { FloatArray(FEATURES) }
                interpreter.run(input, output)
                return output[0]
            } finally {
                if (scaled !== crop) scaled.recycle()
            }
        } finally {
            if (crop !== image) crop.recycle()
        }
    }

    override fun close() = interpreter.close()
}
