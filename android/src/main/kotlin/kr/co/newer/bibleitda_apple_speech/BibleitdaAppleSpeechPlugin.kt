package kr.co.newer.bibleitda_apple_speech

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executors

class BibleitdaAppleSpeechPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val preparationExecutor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activeSession: WhisperSpeechSession? = null
    private var nativeContext = 0L
    private var pendingStart: PendingStart? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "bibleitda_apple_speech/methods")
        eventChannel = EventChannel(binding.binaryMessenger, "bibleitda_apple_speech/events")
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activeSession?.cancel {}
        activeSession = null
        // The process owns the native context. Avoid freeing it while a queued
        // transcription may still be returning during Flutter engine teardown.
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        preparationExecutor.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> result.success(
                mapOf(
                    "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
                    "systemVersion" to Build.VERSION.RELEASE,
                    "minimumVersion" to "7.0",
                ),
            )
            "start" -> {
                val locale = call.argument<String>("localeIdentifier") ?: "ko_KR"
                startWithPermission(locale, result)
            }
            "stop" -> {
                val session = activeSession
                activeSession = null
                if (session == null) result.success(null)
                else session.stop { mainHandler.post { result.success(null) } }
            }
            "cancel" -> {
                val session = activeSession
                activeSession = null
                if (session == null) result.success(null)
                else session.cancel { mainHandler.post { result.success(null) } }
            }
            else -> result.notImplemented()
        }
    }

    private fun startWithPermission(locale: String, result: MethodChannel.Result) {
        if (applicationContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            prepareAndStart(locale, result)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success("permission_denied")
            return
        }
        pendingStart?.result?.success("listen_error")
        pendingStart = PendingStart(locale, result)
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
    }

    private fun prepareAndStart(locale: String, result: MethodChannel.Result) {
        activeSession?.cancel {}
        activeSession = null
        emit(mapOf("type" to "status", "status" to "preparing_model", "engine" to "whisper_cpp_tiny_android"))
        preparationExecutor.execute {
            try {
                if (nativeContext == 0L) {
                    val model = WhisperModelStore.prepare(applicationContext, ::emit)
                    nativeContext = WhisperNative.createContext(model.absolutePath)
                    check(nativeContext != 0L) { "Unable to load the Whisper tiny model." }
                    emit(mapOf("type" to "diagnostic", "message" to "whisper_model_ready:tiny:77691713:android"))
                }
                mainHandler.post {
                    try {
                        val session = WhisperSpeechSession(nativeContext, locale, ::emit)
                        activeSession = session
                        session.start()
                        result.success("started:whisper_cpp_tiny_android")
                    } catch (error: Exception) {
                        activeSession = null
                        emitError("listen_error", error)
                        result.success("listen_error")
                    }
                }
            } catch (error: Exception) {
                emitError("model_error", error)
                mainHandler.post { result.success("listen_error") }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val pending = pendingStart ?: return true
        pendingStart = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            prepareAndStart(pending.locale, pending.result)
        } else {
            pending.result.success("permission_denied")
        }
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(value: Map<String, Any>) {
        mainHandler.post { eventSink?.success(value) }
    }

    private fun emitError(code: String, error: Throwable) {
        emit(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to (error.message ?: error.javaClass.simpleName),
            ),
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    private data class PendingStart(
        val locale: String,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val PERMISSION_REQUEST = 53_071
    }
}
