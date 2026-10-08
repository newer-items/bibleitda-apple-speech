package kr.co.newer.bibleitda_apple_speech

internal object WhisperNative {
    init {
        System.loadLibrary("bibleitda_whisper")
    }

    external fun createContext(modelPath: String): Long
    external fun freeContext(context: Long)
    external fun transcribe(context: Long, samples: FloatArray, language: String, prompt: String): String
}
