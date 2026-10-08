#include <jni.h>
#include <algorithm>
#include <string>
#include <thread>
#include "whisper.h"

namespace {
std::string to_string(JNIEnv *env, jstring value) {
    if (value == nullptr) return "ko";
    const char *chars = env->GetStringUTFChars(value, nullptr);
    std::string result = chars == nullptr ? "ko" : chars;
    if (chars != nullptr) env->ReleaseStringUTFChars(value, chars);
    return result;
}
}

extern "C" JNIEXPORT jlong JNICALL
Java_kr_co_newer_bibleitda_1apple_1speech_WhisperNative_createContext(
    JNIEnv *env, jobject, jstring model_path) {
    const std::string path = to_string(env, model_path);
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = false;
    params.flash_attn = false;
    return reinterpret_cast<jlong>(whisper_init_from_file_with_params(path.c_str(), params));
}

extern "C" JNIEXPORT void JNICALL
Java_kr_co_newer_bibleitda_1apple_1speech_WhisperNative_freeContext(
    JNIEnv *, jobject, jlong pointer) {
    if (pointer != 0) whisper_free(reinterpret_cast<whisper_context *>(pointer));
}

extern "C" JNIEXPORT jstring JNICALL
Java_kr_co_newer_bibleitda_1apple_1speech_WhisperNative_transcribe(
    JNIEnv *env, jobject, jlong pointer, jfloatArray audio, jstring language, jstring prompt) {
    auto *context = reinterpret_cast<whisper_context *>(pointer);
    if (context == nullptr || audio == nullptr) return env->NewStringUTF("");

    const jsize count = env->GetArrayLength(audio);
    if (count <= 0) return env->NewStringUTF("");
    jfloat *samples = env->GetFloatArrayElements(audio, nullptr);
    if (samples == nullptr) return env->NewStringUTF("");

    const std::string language_code = to_string(env, language);
    const std::string prompt_text = prompt == nullptr ? std::string() : to_string(env, prompt);
    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = std::min(4, std::max(1, static_cast<int>(std::thread::hardware_concurrency())));
    params.translate = false;
    params.detect_language = false;
    params.language = language_code.c_str();
    params.max_tokens = 128;
    params.single_segment = true;
    params.no_context = true;
    params.no_timestamps = true;
    params.suppress_blank = true;
    params.suppress_nst = true;
    params.greedy.best_of = 1;
    params.temperature = 0.0f;
    params.temperature_inc = 0.0f;
    params.no_speech_thold = 0.30f;
    // English only: vocabulary prompt from the passage (empty for Korean).
    params.initial_prompt = prompt_text.empty() ? nullptr : prompt_text.c_str();
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;

    const int status = whisper_full(context, params, samples, count);
    env->ReleaseFloatArrayElements(audio, samples, JNI_ABORT);
    if (status != 0) return env->NewStringUTF("");

    std::string text;
    const int segments = whisper_full_n_segments(context);
    for (int i = 0; i < segments; ++i) {
        const char *segment = whisper_full_get_segment_text(context, i);
        if (segment != nullptr) text += segment;
    }
    return env->NewStringUTF(text.c_str());
}
