package com.outsystems.experts.cdvaivoice

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.CallbackContext
import org.json.JSONArray
import java.lang.Exception
import java.util.Locale

class CdvAiVoice : CordovaPlugin() {

    companion object {
        const val PERMISSION_REQUEST_CODE = 1001

        private const val START_LISTENING = "startListening"
        private const val STOP_LISTENING = "stopListening"
        private const val SPEAK = "speak"
    }

    private var startListeningCallback: CallbackContext? = null
    private var stopListeningCallback: CallbackContext? = null
    private var speakCallback: CallbackContext? = null
    private lateinit var textToSpeech: TextToSpeech
    private var speechRecognizer: SpeechRecognizer? = null
    private var recognizedText: String = ""
    private lateinit var currentAction: String
    private lateinit var speakText: String

    override fun execute(action: String, args: JSONArray, callbackContext: CallbackContext): Boolean {
        return when (action) {
            START_LISTENING -> {
                this.startListeningCallback = callbackContext
                currentAction = START_LISTENING
                if (hasAudioPermission()) {
                    cordova.activity.runOnUiThread {
                        startListening()
                    }
                } else {
                    requestAudioPermission()
                }
                true
            }
            SPEAK -> {
                this.speakCallback = callbackContext
                currentAction = SPEAK
                if (hasAudioPermission()) {
                    val text = args.getString(0)
                    speakText = text
                    cordova.activity.runOnUiThread {
                        speak(text)
                    }
                } else {
                    requestAudioPermission()
                }

                true
            }
            STOP_LISTENING -> {
                this.stopListeningCallback = callbackContext
                cordova.activity.runOnUiThread {
                    stopListening()
                }
                true
            }
            else -> {
                false
            }
        }
    }

    private fun hasAudioPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cordova.activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestAudioPermission() {
        cordova.requestPermissions(this, PERMISSION_REQUEST_CODE, arrayOf(Manifest.permission.RECORD_AUDIO))
    }

    private fun startListening() {
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(cordova.activity)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
        }
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray) {}
            override fun onEndOfSpeech() {
                // Do not stop listening automatically
            }
            override fun onError(error: Int) {
                startListeningCallback?.error("Error occurred: $error")
                startListeningCallback = null
            }
            override fun onResults(results: Bundle) {
                val matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                recognizedText = matches?.lastOrNull() ?: ""
                startListeningCallback?.success(recognizedText)
                startListeningCallback = null
                // Restart listening after getting results
                startListening()
            }
            override fun onPartialResults(partialResults: Bundle) {}
            override fun onEvent(eventType: Int, params: Bundle) {}
        })
        speechRecognizer?.startListening(intent)
    }

    private fun stopListening() {
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
            speechRecognizer = null
            // Return the recognized text when stopListening is called
            if (stopListeningCallback != null) {
                stopListeningCallback?.success(recognizedText)
                stopListeningCallback = null
            }
        } catch (ex: Exception) {
            stopListeningCallback?.error(ex.message.toString())
            stopListeningCallback = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if ((grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)) {
                cordova.activity.runOnUiThread {
                    if (currentAction == START_LISTENING) {
                        startListening()
                    } else {
                        speak(speakText)
                    }
                }
            } else {
                speakCallback?.error("Permission denied")
                startListeningCallback?.error("Permission denied")
            }
        }
    }

    private fun speak(textToSpeak: String) {
        textToSpeech = TextToSpeech(cordova.context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech.language = Locale.US
                textToSpeech.setSpeechRate(1.0f)

                val result = textToSpeech.speak(textToSpeak, TextToSpeech.QUEUE_FLUSH, null, null)
                if (result == TextToSpeech.ERROR) {
                    println("Error in converting Text to Speech!")
                    speakCallback?.error("Error in converting Text to Speech!")
                }
            } else {
                speakCallback?.error("Initialization of TextToSpeech failed!")
                println("Initialization of TextToSpeech failed!")
            }
        }
    }
}