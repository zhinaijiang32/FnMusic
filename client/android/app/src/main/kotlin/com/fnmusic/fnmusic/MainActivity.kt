package com.fnmusic.fnmusic

import android.Manifest
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private companion object {
        const val channelName = "fnmusic/audio_meter"
        const val recordAudioRequest = 35017
    }

    private var visualizer: Visualizer? = null
    private var requestedPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getOutputPeak" -> result.success(readOutputPeak())
                    "getOutputSpectrum" -> result.success(readOutputSpectrum())
                    else -> result.notImplemented()
                }
            }
    }

    private fun readOutputPeak(): Double {
        val spectrum = readOutputSpectrum()
        return spectrum.maxOrNull() ?: 0.0
    }

    private fun readOutputSpectrum(): List<Double> {
        val bands = 64
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            if (!requestedPermission) {
                requestedPermission = true
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), recordAudioRequest)
            }
            return List(bands) { 0.0 }
        }

        return try {
            val activeVisualizer = visualizer ?: Visualizer(0).also { created ->
                created.captureSize = Visualizer.getCaptureSizeRange().last()
                created.enabled = true
                visualizer = created
            }
            val fft = ByteArray(activeVisualizer.captureSize)
            if (activeVisualizer.getFft(fft) != Visualizer.SUCCESS) {
                return List(bands) { 0.0 }
            }

            // Android returns interleaved real/imaginary FFT components.
            // Combine logarithmic bin ranges into 64 visible frequency bands.
            val fftBins = fft.size / 2
            List(bands) { band ->
                val start = max(1, (fftBins.toDouble().pow(band.toDouble() / bands)).toInt())
                val end = max(start + 1,
                    (fftBins.toDouble().pow((band + 1.0) / bands)).toInt())
                    .coerceAtMost(fftBins - 1)
                var strongest = 0.0
                for (bin in start..end) {
                    val real = fft[bin * 2].toDouble()
                    val imaginary = fft[bin * 2 + 1].toDouble()
                    strongest = max(strongest, sqrt(real * real + imaginary * imaginary) / 128.0)
                }
                // Compress the wide FFT dynamic range for a readable UI while
                // preserving the frequency relationship between the bars.
                min(1.0, sqrt(strongest) * 0.92)
            }
        } catch (_: Exception) {
            List(bands) { 0.0 }
        }
    }

    override fun onDestroy() {
        visualizer?.release()
        visualizer = null
        super.onDestroy()
    }
}
