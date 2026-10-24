/*
 *     Ongaku — an Apple Music style edition of Musify.
 *     Based on Musify, Copyright (C) 2026 Valeri Gokadze.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version. See <https://www.gnu.org/licenses/>.
 */

package com.orikami.ongaku.sound

import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Virtualizer
import android.media.audiofx.Visualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Calibrated sound for Ongaku, on the player's audio session:
 * a 10-band equalizer with a limiter (DynamicsProcessing, Android 9+),
 * stereo widening, the current output (speaker, Bluetooth, wired, car),
 * a microphone measurement of a sine sweep, test tones and a live spectrum.
 */
class OngakuSoundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        /** Band centres in Hz, shared with the Dart side. */
        val CENTRES = floatArrayOf(31f, 62f, 125f, 250f, 500f, 1000f, 2000f, 4000f, 8000f, 16000f)
        const val RATE = 48000

        /** Launcher aliases in the app manifest, one per theme. */
        const val PALETTE_ALIAS = "com.orikami.ongaku.palette."
    }

    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var routes: EventChannel
    private lateinit var spectrum: EventChannel
    private val main = Handler(Looper.getMainLooper())

    private var sessionId = 0

    /** Effects per audio session: the player's, plus the crossfade's. */
    private class Effects(val session: Int) {
        var eq: DynamicsProcessing? = null
        var virtualizer: Virtualizer? = null
    }

    private val effects = mutableMapOf<Int, Effects>()
    private var visualizer: Visualizer? = null
    private var gains = FloatArray(CENTRES.size)
    private var enabled = false
    private var widening = 0

    private var routeSink: EventChannel.EventSink? = null
    private var spectrumSink: EventChannel.EventSink? = null
    private var tone: AudioTrack? = null

    private val audioManager get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "ongaku_sound")
        methods.setMethodCallHandler(this)
        routes = EventChannel(binding.binaryMessenger, "ongaku_sound/route")
        routes.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                routeSink = events
                audioManager.registerAudioDeviceCallback(deviceCallback, main)
                val filter = IntentFilter().apply {
                    addAction(UiModeManager.ACTION_ENTER_CAR_MODE)
                    addAction(UiModeManager.ACTION_EXIT_CAR_MODE)
                }
                if (Build.VERSION.SDK_INT >= 33) {
                    context.registerReceiver(carReceiver, filter, Context.RECEIVER_EXPORTED)
                } else {
                    context.registerReceiver(carReceiver, filter)
                }
                events.success(currentRoute())
            }

            override fun onCancel(arguments: Any?) {
                routeSink = null
                audioManager.unregisterAudioDeviceCallback(deviceCallback)
                try {
                    context.unregisterReceiver(carReceiver)
                } catch (_: Exception) {
                }
            }
        })
        spectrum = EventChannel(binding.binaryMessenger, "ongaku_sound/spectrum")
        spectrum.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                spectrumSink = events
                startVisualizer()
            }

            override fun onCancel(arguments: Any?) {
                spectrumSink = null
                stopVisualizer()
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        for (id in effects.keys.toList()) release(id)
        stopVisualizer()
        tone?.release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= 28)
                "attach" -> {
                    val id = call.argument<Int>("sessionId") ?: 0
                    if (id != sessionId) {
                        release(sessionId)
                        sessionId = id
                        if (spectrumSink != null) startVisualizer()
                    }
                    result.success(applyAll())
                }
                "attachExtra" -> {
                    val id = call.argument<Int>("sessionId") ?: 0
                    if (id != 0) effects.getOrPut(id) { Effects(id) }
                    result.success(applyAll())
                }
                "detachExtra" -> {
                    val id = call.argument<Int>("sessionId") ?: 0
                    if (id != sessionId) release(id)
                    result.success(true)
                }
                "setGains" -> {
                    val list = call.argument<List<Double>>("gains") ?: emptyList()
                    gains = FloatArray(CENTRES.size) { list.getOrElse(it) { 0.0 }.toFloat() }
                    enabled = call.argument<Boolean>("enabled") ?: true
                    result.success(applyAll())
                }
                "setWidening" -> {
                    widening = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                    result.success(applyAll())
                }
                "route" -> result.success(currentRoute())
                "noiseLevel" -> background(result) { noiseLevel(call.argument<Int>("ms") ?: 1500) }
                "measure" -> background(result) {
                    measure(
                        (call.argument<Double>("f1") ?: 20.0),
                        (call.argument<Double>("f2") ?: 20000.0),
                        call.argument<Int>("sweepMs") ?: 6000,
                        call.argument<Double>("level") ?: -6.0,
                    )
                }
                "playTone" -> {
                    playTone(
                        call.argument<Double>("frequency") ?: 1000.0,
                        call.argument<Double>("level") ?: -30.0,
                        call.argument<Int>("ms") ?: 800,
                        call.argument<Double>("pan") ?: 0.0,
                    )
                    result.success(true)
                }
                "stopTone" -> {
                    tone?.let {
                        try {
                            it.stop()
                        } catch (_: Exception) {
                        }
                        it.release()
                    }
                    tone = null
                    result.success(true)
                }
                // Not sound, but the same small native bridge: the app icon
                // of the chosen theme (one launcher alias per palette).
                "setLauncherIcon" -> result.success(
                    setLauncherIcon(call.argument<String>("palette") ?: "ongaku"),
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ongaku_sound", e.message, null)
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("ongaku_sound", e.message, null) }
            }
        }.start()
    }

    // --- Equalizer and widening on the player's session -------------------

    private fun applyAll(): Boolean {
        if (Build.VERSION.SDK_INT < 28) return false
        if (sessionId != 0) effects.getOrPut(sessionId) { Effects(sessionId) }
        var ok = effects.isNotEmpty()
        for (fx in effects.values) ok = applyEq(fx) and applyWidening(fx) and ok
        return ok
    }

    private fun applyEq(fx: Effects): Boolean {
        if (Build.VERSION.SDK_INT < 28) return false
        try {
            var dp = fx.eq
            if (dp == null) {
                val builder = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    2,
                    false, 0,
                    false, 0,
                    true, CENTRES.size,
                    true,
                )
                val config = builder.build()
                config.setPostEqAllChannelsTo(buildEq())
                config.setLimiterAllChannelsTo(
                    DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -1f, 0f),
                )
                dp = DynamicsProcessing(0, fx.session, config)
                fx.eq = dp
            } else {
                dp.setPostEqAllChannelsTo(buildEq())
            }
            // Headroom for boosts; the limiter catches what is left.
            val boost = gains.maxOrNull() ?: 0f
            dp.setInputGainAllChannelsTo(if (enabled) -max(0f, boost) * 0.6f else 0f)
            dp.enabled = enabled
            return true
        } catch (e: Exception) {
            fx.eq = null
            return false
        }
    }

    private fun buildEq(): DynamicsProcessing.Eq {
        val eqConfig = DynamicsProcessing.Eq(true, true, CENTRES.size)
        for (i in CENTRES.indices) {
            val cutoff = if (i == CENTRES.size - 1) 20000f else sqrt(CENTRES[i] * CENTRES[i + 1])
            eqConfig.setBand(i, DynamicsProcessing.EqBand(true, cutoff, if (enabled) gains[i] else 0f))
        }
        return eqConfig
    }

    private fun applyWidening(fx: Effects): Boolean {
        try {
            if (widening == 0) {
                fx.virtualizer?.enabled = false
                return true
            }
            val v = fx.virtualizer ?: Virtualizer(0, fx.session).also { fx.virtualizer = it }
            if (v.strengthSupported) v.setStrength(widening.toShort())
            v.enabled = true
            return true
        } catch (e: Exception) {
            fx.virtualizer = null
            return widening == 0
        }
    }

    private fun release(session: Int) {
        val fx = effects.remove(session) ?: return
        try {
            fx.eq?.release()
        } catch (_: Exception) {
        }
        try {
            fx.virtualizer?.release()
        } catch (_: Exception) {
        }
    }

    // --- Output route -----------------------------------------------------

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) = emitRoute()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) = emitRoute()
    }

    private val carReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = emitRoute()
    }

    private fun emitRoute() {
        main.postDelayed({ routeSink?.success(currentRoute()) }, 300)
    }

    private fun currentRoute(): Map<String, Any> {
        val uiMode = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        if (uiMode.currentModeType == Configuration.UI_MODE_TYPE_CAR) {
            return mapOf("type" to "car", "name" to "", "id" to "car")
        }
        val devices: List<AudioDeviceInfo> = if (Build.VERSION.SDK_INT >= 33) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            audioManager.getAudioDevicesForAttributes(attributes)
        } else {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        }
        fun pick(vararg types: Int) = devices.firstOrNull { it.type in types }
        val bluetooth = pick(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_BLE_BROADCAST,
        )
        if (bluetooth != null) {
            val name = bluetooth.productName?.toString() ?: ""
            return mapOf("type" to "bluetooth", "name" to name, "id" to "bt:$name")
        }
        val wired = pick(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
        )
        if (wired != null) {
            val name = wired.productName?.toString() ?: ""
            return mapOf("type" to "wired", "name" to name, "id" to "wired:$name")
        }
        return mapOf("type" to "speaker", "name" to "", "id" to "speaker")
    }

    // --- Microphone measurement -------------------------------------------

    private fun newRecorder(): AudioRecord {
        val unprocessed = audioManager.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        val source = if (unprocessed) MediaRecorder.AudioSource.UNPROCESSED else MediaRecorder.AudioSource.VOICE_RECOGNITION
        val minBuffer = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        return AudioRecord(source, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, max(minBuffer, RATE))
    }

    private fun record(recorder: AudioRecord, samples: Int): FloatArray {
        val out = FloatArray(samples)
        var read = 0
        while (read < samples) {
            val n = recorder.read(out, read, min(4096, samples - read), AudioRecord.READ_BLOCKING)
            if (n <= 0) break
            read += n
        }
        return out
    }

    /** Ambient noise in dBFS, to check the room is quiet enough. */
    private fun noiseLevel(ms: Int): Double {
        val recorder = newRecorder()
        try {
            recorder.startRecording()
            record(recorder, RATE / 5) // let the input settle
            val data = record(recorder, RATE * ms / 1000)
            var sum = 0.0
            for (v in data) sum += v * v
            return 10 * log10(max(sum / max(1, data.size), 1e-12))
        } finally {
            recorder.stop()
            recorder.release()
        }
    }

    /**
     * Plays an exponential sine sweep from [f1] to [f2] on the current
     * media output while the microphone records. Returns the recording and
     * the sample where the sweep was queued.
     */
    private fun measure(f1: Double, f2: Double, sweepMs: Int, level: Double): Map<String, Any> {
        val sweepSamples = RATE * sweepMs / 1000
        val lead = RATE / 2
        val tail = RATE
        val amplitude = 10.0.pow(level / 20.0)
        val signal = FloatArray(lead + sweepSamples + tail)
        val k = ln(f2 / f1)
        val duration = sweepSamples.toDouble() / RATE
        val fade = RATE / 50
        for (i in 0 until sweepSamples) {
            val t = i.toDouble() / RATE
            val phase = 2 * PI * f1 * duration / k * (exp(t / duration * k) - 1)
            var gain = amplitude
            if (i < fade) gain *= i.toDouble() / fade
            if (i > sweepSamples - fade) gain *= (sweepSamples - i).toDouble() / fade
            signal[lead + i] = (sin(phase) * gain).toFloat()
        }

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(signal.size * 4)
            .build()
        track.write(signal, 0, signal.size, AudioTrack.WRITE_BLOCKING)

        val recorder = newRecorder()
        try {
            recorder.startRecording()
            record(recorder, RATE / 5)
            track.play()
            val data = record(recorder, signal.size + RATE / 2)
            return mapOf(
                "sampleRate" to RATE,
                "samples" to data,
                "sweepStart" to lead,
                "sweepSamples" to sweepSamples,
                "f1" to f1,
                "f2" to f2,
            )
        } finally {
            try {
                track.stop()
            } catch (_: Exception) {
            }
            track.release()
            recorder.stop()
            recorder.release()
        }
    }

    // --- Hearing test tones -----------------------------------------------

    private fun playTone(frequency: Double, level: Double, ms: Int, pan: Double) {
        tone?.release()
        val samples = RATE * ms / 1000
        val amplitude = 10.0.pow(level / 20.0)
        val fade = RATE / 25
        val data = FloatArray(samples * 2)
        val left = if (pan > 0) 1 - pan else 1.0
        val right = if (pan < 0) 1 + pan else 1.0
        for (i in 0 until samples) {
            var gain = amplitude
            if (i < fade) gain *= i.toDouble() / fade
            if (i > samples - fade) gain *= (samples - i).toDouble() / fade
            val v = sin(2 * PI * frequency * i / RATE) * gain
            data[2 * i] = (v * left).toFloat()
            data[2 * i + 1] = (v * right).toFloat()
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(data.size * 4)
            .build()
        track.write(data, 0, data.size, AudioTrack.WRITE_BLOCKING)
        track.play()
        tone = track
    }

    // --- Live spectrum for the automatic layer ----------------------------

    private fun startVisualizer() {
        stopVisualizer()
        if (sessionId == 0) return
        try {
            val v = Visualizer(sessionId)
            v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            v.scalingMode = Visualizer.SCALING_MODE_AS_PLAYED
            val rate = min(Visualizer.getMaxCaptureRate(), 4000) // 4 per second
            v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(v: Visualizer?, data: ByteArray?, rate: Int) {}

                override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null) return
                    spectrumSink?.success(bandLevels(fft, samplingRate / 1000.0))
                }
            }, rate, false, true)
            v.enabled = true
            visualizer = v
        } catch (e: Exception) {
            spectrumSink?.error("ongaku_sound", e.message, null)
        }
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
        }
        visualizer = null
    }

    /** Energy per band in dB from Visualizer FFT bytes (real, imag pairs). */
    private fun bandLevels(fft: ByteArray, sampleRate: Double): DoubleArray {
        val bins = fft.size / 2
        val binHz = sampleRate / 2 / bins
        val energy = DoubleArray(CENTRES.size)
        for (b in 1 until bins) {
            val re = fft[2 * b].toDouble()
            val im = fft[2 * b + 1].toDouble()
            val f = b * binHz
            var band = 0
            while (band < CENTRES.size - 1 && f > sqrt(CENTRES[band].toDouble() * CENTRES[band + 1])) band++
            energy[band] += re * re + im * im
        }
        return DoubleArray(CENTRES.size) { 10 * log10(max(energy[it], 1e-9)) }
    }

    /** Enables the launcher alias of [palette] and disables the others. */
    private fun setLauncherIcon(palette: String): Boolean {
        val pm = context.packageManager
        val wanted = "$PALETTE_ALIAS$palette"
        @Suppress("DEPRECATION")
        val activities = pm.getPackageInfo(
            context.packageName,
            PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS,
        ).activities ?: return false
        val aliases = activities.map { it.name }.filter { it.startsWith(PALETTE_ALIAS) }
        if (wanted !in aliases) return false
        // Enable the new icon first, so the app always keeps one.
        for (name in listOf(wanted) + aliases.filter { it != wanted }) {
            val state = if (name == wanted) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            val component = ComponentName(context.packageName, name)
            if (pm.getComponentEnabledSetting(component) != state) {
                pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            }
        }
        return true
    }

}
