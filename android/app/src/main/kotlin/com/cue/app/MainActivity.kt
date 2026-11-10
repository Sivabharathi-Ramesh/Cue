package com.cue.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
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
 *
 * The activity also turns a long press of the volume-down key into a
 * press-to-talk trigger. A physical key is easier to find by touch than a
 * multi-finger gesture, and it works while TalkBack is running. A short press
 * still changes the volume, so the key keeps its normal job.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "cue/feedback"
    private val keysChannelName = "cue/keys"
    private val sensorsChannelName = "cue/sensors"
    private val deviceChannelName = "cue/device"
    private val imageChannelName = "cue/image"
    private val locationChannelName = "cue/location"

    private var keysChannel: MethodChannel? = null
    private var volumeHoldStarted = false

    /**
     * One background worker for frame-to-JPEG conversion.
     *
     * Pure-Dart JPEG encoding took over six seconds for a 720p frame, which
     * made live object narration impossible. Android's own YUV encoder does
     * the same work in milliseconds, so the picture is built here and handed
     * back as a JPEG the detector can decode.
     */
    private val imageExecutor = Executors.newSingleThreadExecutor()

    /// Location lookups block on the GPS/network provider, so they never run on
    /// the UI thread.
    private val locationExecutor = Executors.newSingleThreadExecutor()

    private var sensorManager: SensorManager? = null
    private var sensorSink: EventChannel.EventSink? = null
    private var sensorsRegistered = false

    /**
     * Ambient light and proximity, streamed to Dart.
     *
     * A blind user cannot see that the room is dark or that the phone is
     * covered by a sleeve. These two sensors answer both questions with no
     * camera frame and no OCR, so the warning arrives before a reading fails.
     */
    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val sink = sensorSink ?: return
            when (event.sensor.type) {
                Sensor.TYPE_LIGHT -> sink.success(
                    mapOf("kind" to "light", "value" to event.values[0].toDouble())
                )
                Sensor.TYPE_PROXIMITY -> {
                    // Most phones report 0 for "near" and the maximum range for
                    // "far"; a few report centimetres. Both compare correctly.
                    val near = event.values[0] < event.sensor.maximumRange
                    sink.success(mapOf("kind" to "proximity", "near" to near))
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    // One handler for the whole activity. removeCallbacks() only removes a
    // runnable from the handler instance it was posted on, so creating a new
    // Handler for every key press would leave the old long-press callback
    // alive. A short press would then start listening 450 ms later, after the
    // user had already let go.
    private val handler = Handler(Looper.getMainLooper())

    private val volumeHoldRunnable = Runnable {
        volumeHoldStarted = true
        keysChannel?.invokeMethod("talkStart", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        keysChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            keysChannelName
        )

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
                    "keepAwake" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        setKeepAwake(on)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            sensorsChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sensorSink = events
                startSensors()
            }

            override fun onCancel(arguments: Any?) {
                sensorSink = null
                stopSensors()
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "depthAvailable" -> result.success(hasDepthCamera())
                    else -> result.notImplemented()
                }
            }

        // "Where am I?" is answered by the phone's own location service and
        // geocoder. Nothing is sent to Cue's own servers, because Cue has none.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> {
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 8000
                        locationExecutor.execute {
                            val payload = try {
                                currentLocationPayload(timeoutMs)
                            } catch (_: Exception) {
                                null
                            }
                            runOnUiThread { result.success(payload) }
                        }
                    }
                    // Location is a phone-wide switch. Android does not let an
                    // app turn it on, so Cue says so and opens the screen where
                    // the user can. Without this the answer is a useless "no
                    // fix" when the switch is simply off.
                    "servicesEnabled" -> result.success(locationServicesEnabled())
                    "openLocationSettings" -> {
                        val opened = try {
                            startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                            true
                        } catch (_: Exception) {
                            false
                        }
                        result.success(opened)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nv21ToJpeg" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val rowStride = call.argument<Int>("rowStride") ?: width
                        val rotation = call.argument<Int>("rotation") ?: 0
                        val maxSide = call.argument<Int>("maxSide") ?: 640
                        val quality = call.argument<Int>("quality") ?: 82

                        if (bytes == null || width <= 0 || height <= 0 ||
                            rowStride < width
                        ) {
                            result.error("bad_args", "Missing frame data", null)
                            return@setMethodCallHandler
                        }

                        imageExecutor.execute {
                            try {
                                val jpeg = nv21ToJpeg(
                                    bytes,
                                    width,
                                    height,
                                    rowStride,
                                    rotation,
                                    maxSide,
                                    quality
                                )
                                runOnUiThread { result.success(jpeg) }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error(
                                        "image_error",
                                        error.message ?: "Could not encode frame",
                                        null
                                    )
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Turns a camera NV21 frame into an upright, downscaled JPEG.
     *
     * The detector letterboxes every image to 640x640, so sending more pixels
     * than [maxSide] only costs time. Rotation happens before compression so
     * the model sees an upright scene, which is what it was trained on.
     */
    private fun nv21ToJpeg(
        data: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        rotation: Int,
        maxSide: Int,
        quality: Int
    ): ByteArray {
        val ySize = rowStride * height
        val uvRows = (height + 1) / 2
        val needed = ySize + rowStride * uvRows
        if (data.size < needed) {
            throw IllegalArgumentException(
                "Frame is ${data.size} bytes, expected $needed"
            )
        }

        // YuvImage wants tightly packed rows. Camera buffers usually pad each
        // row, so copy row by row into a compact buffer first.
        val tight = ByteArray(width * height * 3 / 2)
        for (row in 0 until height) {
            System.arraycopy(data, row * rowStride, tight, row * width, width)
        }
        for (row in 0 until uvRows) {
            System.arraycopy(
                data,
                ySize + row * rowStride,
                tight,
                width * height + row * width,
                width
            )
        }

        val yuv = YuvImage(tight, ImageFormat.NV21, width, height, null)
        val firstPass = ByteArrayOutputStream()
        yuv.compressToJpeg(Rect(0, 0, width, height), 90, firstPass)
        val raw = firstPass.toByteArray()
        val bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size)
            ?: throw IllegalStateException("Could not decode the camera frame")

        val matrix = Matrix()
        if (rotation % 360 != 0) matrix.postRotate(rotation.toFloat())
        val longSide = maxOf(bitmap.width, bitmap.height)
        val scale = if (maxSide > 0 && longSide > maxSide) {
            maxSide.toFloat() / longSide
        } else {
            1f
        }
        if (scale < 1f) matrix.postScale(scale, scale)

        val upright = if (rotation % 360 == 0 && scale >= 1f) {
            bitmap
        } else {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }

        val output = ByteArrayOutputStream()
        upright.compress(Bitmap.CompressFormat.JPEG, quality, output)
        if (upright !== bitmap) upright.recycle()
        bitmap.recycle()
        return output.toByteArray()
    }

    override fun onDestroy() {
        imageExecutor.shutdown()
        super.onDestroy()
    }

    private fun startSensors() {
        if (sensorsRegistered) return
        val manager = getSystemService(SENSOR_SERVICE) as? SensorManager ?: return
        sensorManager = manager

        val light = manager.getDefaultSensor(Sensor.TYPE_LIGHT)
        val proximity = manager.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        if (light == null && proximity == null) return

        // Normal rate is enough: light changes slowly and the reading is used
        // for a warning, not for photography.
        if (light != null) {
            manager.registerListener(sensorListener, light, SensorManager.SENSOR_DELAY_NORMAL)
        }
        if (proximity != null) {
            manager.registerListener(
                sensorListener,
                proximity,
                SensorManager.SENSOR_DELAY_NORMAL
            )
        }
        sensorsRegistered = true
    }

    private fun stopSensors() {
        if (!sensorsRegistered) return
        try {
            sensorManager?.unregisterListener(sensorListener)
        } catch (_: Throwable) {
            // Unregistering a listener that was never registered is harmless.
        }
        sensorsRegistered = false
    }

    /**
     * Whether any camera on this phone can expose a depth stream.
     *
     * This is a capability probe, not a depth reader. Android only exposes
     * real depth through camera2's DEPTH_OUTPUT, which cannot be opened while
     * the Flutter camera plugin holds its own session. Knowing the answer
     * lets Cue decide whether a depth-based upgrade is even possible on this
     * handset.
     */
    private fun hasDepthCamera(): Boolean {
        return try {
            val manager = getSystemService(CAMERA_SERVICE) as CameraManager
            manager.cameraIdList.any { id ->
                val characteristics = manager.getCameraCharacteristics(id)
                val capabilities = characteristics.get(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES
                ) ?: IntArray(0)
                capabilities.contains(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_DEPTH_OUTPUT
                )
            }
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Whether the phone-wide Location switch is on.
     *
     * This is separate from the app permission: permission can be granted
     * while the switch is off, and in that state no provider will ever deliver
     * a fix. Telling the user to go outside would then be wrong.
     */
    private fun locationServicesEnabled(): Boolean {
        val manager = getSystemService(LOCATION_SERVICE) as? LocationManager
            ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.isLocationEnabled
            } else {
                manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * One location fix plus whatever place name the geocoder can supply.
     *
     * `null` means "no usable position", which the caller reports honestly
     * instead of inventing a place. A cached fix under two minutes old is
     * preferred: the user asking "where am I?" wants an answer now, not a
     * satellite hunt.
     */
    private fun currentLocationPayload(timeoutMs: Int): Map<String, Any?>? {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine != PackageManager.PERMISSION_GRANTED &&
            coarse != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        if (!locationServicesEnabled()) return null

        val manager = getSystemService(LOCATION_SERVICE) as? LocationManager ?: return null
        val fix = bestLocation(manager, timeoutMs) ?: return null
        val place = placeNames(fix)

        return mapOf(
            "latitude" to fix.latitude,
            "longitude" to fix.longitude,
            "accuracy" to fix.accuracy.toDouble(),
            "locality" to place["locality"],
            "subLocality" to place["subLocality"],
            "city" to place["city"],
            "state" to place["state"],
            "country" to place["country"]
        )
    }

    private fun bestLocation(manager: LocationManager, timeoutMs: Int): Location? {
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        ).filter { provider ->
            try {
                manager.isProviderEnabled(provider)
            } catch (_: Exception) {
                false
            }
        }

        var cached: Location? = null
        for (provider in providers) {
            val location = try {
                manager.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            } catch (_: Exception) {
                null
            }
            if (location != null && (cached == null || location.time > cached!!.time)) {
                cached = location
            }
        }

        val age = cached?.let { System.currentTimeMillis() - it.time } ?: Long.MAX_VALUE
        if (cached != null && age < 2 * 60 * 1000) return cached

        return requestSingleFix(manager, providers, timeoutMs) ?: cached
    }

    private fun requestSingleFix(
        manager: LocationManager,
        providers: List<String>,
        timeoutMs: Int
    ): Location? {
        // Network first indoors: GPS needs the sky, and a locality name is all
        // this answer needs.
        val provider = when {
            providers.contains(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            providers.contains(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            else -> return null
        }

        val latch = CountDownLatch(1)
        var received: Location? = null
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (received == null) {
                    received = location
                    latch.countDown()
                }
            }

            override fun onProviderDisabled(provider: String) {
                latch.countDown()
            }

            override fun onProviderEnabled(provider: String) {}

            @Deprecated("Required by LocationListener on older Android versions")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        return try {
            manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            latch.await(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            received
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        } finally {
            try {
                manager.removeUpdates(listener)
            } catch (_: Exception) {
                // Removing an unused listener is not an error.
            }
        }
    }

    private fun placeNames(location: Location): Map<String, String?> {
        if (!Geocoder.isPresent()) return emptyMap()

        return try {
            val geocoder = Geocoder(this, Locale.getDefault())
            @Suppress("DEPRECATION")
            val addresses = geocoder.getFromLocation(location.latitude, location.longitude, 1)
            val address = addresses?.firstOrNull() ?: return emptyMap()
            mapOf(
                "locality" to address.locality,
                "subLocality" to address.subLocality,
                "city" to (address.locality ?: address.subAdminArea),
                "state" to address.adminArea,
                "country" to address.countryName
            )
        } catch (_: Exception) {
            // No network, or no geocoder data for this country. Coordinates
            // are still a truthful answer.
            emptyMap()
        }
    }

    /**
     * Volume-down long press starts a voice command.
     *
     * The key-down event is consumed so the volume does not slide down while
     * the user holds the key. If the key is released before [volumeHoldMs],
     * the press was a normal volume press, so the stream volume is lowered by
     * one step here instead.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    volumeHoldStarted = false
                    handler.postDelayed(volumeHoldRunnable, volumeHoldMs)
                }
                return true
            }

            KeyEvent.ACTION_UP -> {
                handler.removeCallbacks(volumeHoldRunnable)
                if (volumeHoldStarted) {
                    volumeHoldStarted = false
                    keysChannel?.invokeMethod("talkEnd", null)
                } else {
                    // A short press never reached the system, so apply the
                    // volume change the user expected.
                    val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                    audio.adjustStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        AudioManager.ADJUST_LOWER,
                        AudioManager.FLAG_SHOW_UI
                    )
                }
                return true
            }
        }

        return super.dispatchKeyEvent(event)
    }

    private companion object {
        /** How long volume-down must be held before it means "talk". */
        const val volumeHoldMs = 450L
    }

    /**
     * Stops the display from sleeping while a reading session is live.
     *
     * A locked screen backgrounds the activity, and a backgrounded activity
     * loses the camera. For a blind user holding the phone at a page, that
     * would end the reading with no warning, so the flag stays on for as long
     * as the live screen is in front.
     */
    private fun setKeepAwake(on: Boolean) {
        runOnUiThread {
            if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
