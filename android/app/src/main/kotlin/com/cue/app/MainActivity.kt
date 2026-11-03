package com.cue.app

import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * Hosts Flutter and supplies the short tones Cue uses for non-speech feedback.
 *
 * No audio package is added to the project: a sine wave through AudioTrack is
 * enough for a tick, a beep and the rising pitch that FR-04 asks for. The
 * channel is deliberately small and fails silently, because audio is feedback
 * and never a reason to interrupt a reading.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "cue/feedback"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "tone" -> {
                        val frequency = call.argument<Double>("frequency") ?: 440.0
                        val durationMs = call.argument<Int>("durationMs") ?: 60
                        val volume = call.argument<Double>("volume") ?: 0.2
                        val pan = call.argument<Double>("pan") ?: 0.0
                        result.success(playTone(frequency, durationMs, volume, pan))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playTone(
        frequency: Double,
        durationMs: Int,
        volume: Double,
        pan: Double
    ): Boolean {
        return try {
            val sampleRate = 44100
            val frames = maxOf(1, sampleRate * durationMs / 1000)
            // Interleaved stereo so "move left" can be heard in the left ear.
            val samples = ShortArray(frames * 2)
            val fade = min(frames / 4, 400)
            val amplitude = (Short.MAX_VALUE * volume.coerceIn(0.0, 1.0)).toInt()
            val angle = (pan.coerceIn(-1.0, 1.0) + 1.0) * PI / 4.0
            val leftGain = kotlin.math.cos(angle)
            val rightGain = kotlin.math.sin(angle)

            for (i in 0 until frames) {
                // Short fades at both ends prevent an audible click.
                val envelope = when {
                    i < fade -> i.toDouble() / fade
                    i > frames - fade -> (frames - i).toDouble() / fade
                    else -> 1.0
                }
                val value =
                    sin(2.0 * PI * frequency * i / sampleRate) * amplitude * envelope
                samples[i * 2] = (value * leftGain).toInt().toShort()
                samples[i * 2 + 1] = (value * rightGain).toInt().toShort()
            }

            val minBuffer = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            // MODE_STATIC wants the whole clip in one buffer, so the clip size
            // wins over the minimum.
            val bufferSize = maxOf(minBuffer, samples.size * 2)

            @Suppress("DEPRECATION")
            val track = AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STATIC
            )

            track.write(samples, 0, samples.size)
            track.play()

            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    track.stop()
                } catch (_: IllegalStateException) {
                    // Already stopped.
                }
                track.release()
            }, (durationMs + 150).toLong())

            true
        } catch (_: Exception) {
            false
        }
    }
}
