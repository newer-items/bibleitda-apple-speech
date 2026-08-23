package kr.co.newer.bibleitda_apple_speech

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Process
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.sqrt

internal class WhisperSpeechSession(
    private val context: Long,
    localeIdentifier: String,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private val language = localeIdentifier.replace('-', '_').substringBefore('_').lowercase().ifBlank { "ko" }
    private val running = AtomicBoolean(false)
    private val inferenceRunning = AtomicBoolean(false)
    private val inferencePending = AtomicBoolean(false)
    private val lock = Any()
    private val samples = GrowingFloatBuffer(MAXIMUM_INFERENCE_SAMPLES * 2)
    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private var recorder: AudioRecord? = null
    private var captureThread: Thread? = null
    private var lastInferenceAt = 0L
    private var lastTranscript = ""

    fun start() {
        val minimumBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        check(minimumBuffer > 0) { "Android microphone buffer is unavailable." }
        val audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minimumBuffer * 2, 8_192),
        )
        check(audioRecord.state == AudioRecord.STATE_INITIALIZED) { "Android microphone is unavailable." }
        recorder = audioRecord
        running.set(true)
        audioRecord.startRecording()
        captureThread = Thread({ captureLoop(audioRecord) }, "bibleitda-whisper-audio").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        emit(mapOf("type" to "diagnostic", "message" to "whisper_audio_engine:AudioRecord:VOICE_RECOGNITION:16000:android"))
        emit(mapOf("type" to "status", "status" to "listening", "engine" to "whisper_cpp_tiny_android"))
    }

    fun stop(onComplete: () -> Unit) {
        stopCapture()
        val snapshot = synchronized(lock) { samples.suffix(MAXIMUM_INFERENCE_SAMPLES) }
        inferenceExecutor.execute {
            if (containsSpeech(snapshot)) emitTranscript(snapshot, true)
            emit(mapOf("type" to "status", "status" to "done", "engine" to "whisper_cpp_tiny_android"))
            inferenceExecutor.shutdown()
            onComplete()
        }
    }

    fun cancel(onComplete: () -> Unit) {
        stopCapture()
        inferenceExecutor.shutdownNow()
        emit(mapOf("type" to "status", "status" to "done", "engine" to "whisper_cpp_tiny_android"))
        onComplete()
    }

    private fun captureLoop(audioRecord: AudioRecord) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val buffer = ShortArray(2_048)
        while (running.get()) {
            val count = audioRecord.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
            if (count <= 0) continue
            synchronized(lock) { samples.append(buffer, count) }
            maybeStartInference()
        }
    }

    private fun maybeStartInference() {
        val now = System.currentTimeMillis()
        val snapshot = synchronized(lock) {
            if (samples.size < MINIMUM_INFERENCE_SAMPLES || now - lastInferenceAt < INFERENCE_INTERVAL_MS) null
            else samples.suffix(MAXIMUM_INFERENCE_SAMPLES)
        } ?: return
        if (!hasRecentSpeech(snapshot)) return
        if (!inferenceRunning.compareAndSet(false, true)) {
            inferencePending.set(true)
            return
        }
        lastInferenceAt = now
        inferenceExecutor.execute {
            emitTranscript(snapshot, false)
            inferenceRunning.set(false)
            if (running.get() && inferencePending.getAndSet(false)) maybeStartInference()
        }
    }

    private fun emitTranscript(snapshot: FloatArray, isFinal: Boolean) {
        val started = System.nanoTime()
        val text = clean(WhisperNative.transcribe(context, snapshot, language))
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        emit(
            mapOf(
                "type" to "diagnostic",
                "message" to "whisper_inference:${if (isFinal) "final" else "partial"}:audio_ms=${snapshot.size * 1_000 / SAMPLE_RATE}:processing_ms=$elapsedMs:android",
            ),
        )
        if (text.isNotEmpty() && (isFinal || text != lastTranscript)) {
            lastTranscript = text
            emit(
                mapOf(
                    "type" to "result",
                    "text" to text,
                    "alternatives" to emptyList<String>(),
                    "isFinal" to isFinal,
                    "engine" to "whisper_cpp_tiny_android",
                ),
            )
        }
    }

    private fun stopCapture() {
        if (!running.getAndSet(false)) return
        try {
            recorder?.stop()
        } catch (_: IllegalStateException) {
        }
        captureThread?.join(1_000)
        recorder?.release()
        recorder = null
        captureThread = null
    }

    private fun clean(value: String): String = value
        .replace("[BLANK_AUDIO]", "")
        .replace("[MUSIC]", "")
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun hasRecentSpeech(value: FloatArray): Boolean {
        val start = maxOf(0, value.size - 32_000)
        return rms(value, start, value.size) >= MINIMUM_RMS
    }

    private fun containsSpeech(value: FloatArray): Boolean {
        var start = 0
        while (start < value.size) {
            val end = min(start + SAMPLE_RATE, value.size)
            if (rms(value, start, end) >= MINIMUM_RMS) return true
            start = end
        }
        return false
    }

    private fun rms(value: FloatArray, start: Int, end: Int): Float {
        if (end <= start) return 0f
        var energy = 0.0
        for (index in start until end) energy += value[index] * value[index]
        return sqrt(energy / (end - start)).toFloat()
    }

    private class GrowingFloatBuffer(initialCapacity: Int) {
        private var values = FloatArray(initialCapacity)
        var size: Int = 0
            private set

        fun append(source: ShortArray, count: Int) {
            ensure(size + count)
            for (index in 0 until count) values[size + index] = source[index] / 32768.0f
            size += count
        }

        fun suffix(maximum: Int): FloatArray {
            val count = min(size, maximum)
            return values.copyOfRange(size - count, size)
        }

        private fun ensure(required: Int) {
            if (required <= values.size) return
            values = values.copyOf(maxOf(required, values.size * 2))
        }
    }

    private companion object {
        const val SAMPLE_RATE = 16_000
        const val MINIMUM_INFERENCE_SAMPLES = 24_000
        const val MAXIMUM_INFERENCE_SAMPLES = 480_000
        const val INFERENCE_INTERVAL_MS = 1_500L
        const val MINIMUM_RMS = 0.0015f
    }
}
