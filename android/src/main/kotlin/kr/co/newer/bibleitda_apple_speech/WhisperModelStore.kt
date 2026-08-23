package kr.co.newer.bibleitda_apple_speech

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

internal object WhisperModelStore {
    private const val MODEL_NAME = "ggml-tiny.bin"
    private const val MODEL_URL =
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
    private const val EXPECTED_SIZE = 77_691_713L
    private const val EXPECTED_SHA256 =
        "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"

    fun prepare(
        context: Context,
        emit: (Map<String, Any>) -> Unit,
    ): File {
        val directory = File(context.filesDir, "BibleitdaSpeech/Models")
        check(directory.exists() || directory.mkdirs()) { "Unable to create the speech model directory." }
        val model = File(directory, MODEL_NAME)
        val marker = File(directory, "$MODEL_NAME.sha256")
        if (isValid(model, marker)) {
            emit(mapOf("type" to "diagnostic", "message" to "whisper_model_cache_hit:tiny:android"))
            return model
        }

        model.delete()
        marker.delete()
        val temporary = File(directory, "$MODEL_NAME.download")
        temporary.delete()
        emit(mapOf("type" to "diagnostic", "message" to "whisper_model_download_started:tiny:$EXPECTED_SIZE:android"))

        val connection = (URL(MODEL_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            requestMethod = "GET"
        }
        try {
            connection.connect()
            check(connection.responseCode in 200..299) {
                "Whisper model download failed (HTTP ${connection.responseCode})."
            }
            val total = connection.contentLengthLong.takeIf { it > 0 } ?: EXPECTED_SIZE
            var received = 0L
            var lastPercent = -1
            connection.inputStream.use { input ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        received += read
                        val percent = ((received * 100) / total).toInt().coerceIn(0, 100)
                        if (percent != lastPercent) {
                            lastPercent = percent
                            emit(
                                mapOf(
                                    "type" to "download",
                                    "status" to "downloading",
                                    "model" to "tiny",
                                    "progress" to (received.toDouble() / total.toDouble()).coerceIn(0.0, 1.0),
                                    "receivedBytes" to received,
                                    "totalBytes" to total,
                                ),
                            )
                        }
                    }
                    output.fd.sync()
                }
            }
        } finally {
            connection.disconnect()
        }

        check(temporary.length() == EXPECTED_SIZE) {
            "Whisper model size is invalid (expected $EXPECTED_SIZE, received ${temporary.length()})."
        }
        check(sha256(temporary) == EXPECTED_SHA256) { "Whisper model checksum verification failed." }
        check(temporary.renameTo(model)) { "Unable to install the Whisper model." }
        marker.writeText(EXPECTED_SHA256)
        emit(mapOf("type" to "diagnostic", "message" to "whisper_model_download_finished:tiny:android"))
        return model
    }

    private fun isValid(model: File, marker: File): Boolean {
        if (!model.isFile || model.length() != EXPECTED_SIZE) return false
        if (marker.readTextOrNull()?.trim() == EXPECTED_SHA256) return true
        if (sha256(model) != EXPECTED_SHA256) return false
        marker.writeText(EXPECTED_SHA256)
        return true
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun File.readTextOrNull(): String? = try {
        if (isFile) readText() else null
    } catch (_: Exception) {
        null
    }
}
