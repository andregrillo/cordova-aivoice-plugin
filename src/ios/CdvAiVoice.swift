import Foundation
import Speech
import AVFoundation

@available(iOS 13, *)
@objc(CdvAiVoice)
class CdvAiVoice: CDVPlugin, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioSession: AVAudioSession?
    static let speechSynthesizer = AVSpeechSynthesizer()

    var recognizedText: String?
    var isProcessing: Bool = false

    @objc(startListening:)
    func startListening(command: CDVInvokedUrlCommand) {
        // Request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else {
                print("Microphone permission not granted")
                // You can call a Cordova callback here to notify the JavaScript side
                return
            }

            DispatchQueue.main.async {
                self.configureAudioSessionAndStartRecognition(command: command)
            }
        }
    }

    private func configureAudioSessionAndStartRecognition(command: CDVInvokedUrlCommand) {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.record, mode: .measurement, options: .duckOthers)
            print("Audio session category set successfully")
            try audioSession?.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session activated successfully")

            // Print current audio route
            let currentRoute = AVAudioSession.sharedInstance().currentRoute
            for output in currentRoute.outputs {
                print("Current audio output: \(output.portType.rawValue) - \(output.portName)")
            }

            // Initialize the audio engine
            audioEngine = AVAudioEngine()

            // Initialize and verify input node
            let inputNode = audioEngine.inputNode
            print("Audio engine input node: \(inputNode)")

            // Initialize and verify output node
            let outputNode = audioEngine.outputNode
            print("Audio engine output node: \(outputNode)")

            speechRecognizer = SFSpeechRecognizer()
            print("Supports on device recognition: \(speechRecognizer?.supportsOnDeviceRecognition == true ? "✅" : "🔴")")

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let speechRecognizer = speechRecognizer,
                  speechRecognizer.isAvailable,
                  let recognitionRequest = recognitionRequest else {
                print("Speech recognizer setup failed")
                return
            }

            speechRecognizer.delegate = self

            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                recognitionRequest.append(buffer)
            }

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                if let error = error {
                    print("Recognition error: \(error.localizedDescription)")
                    self?.stopAndReturnResult(command: command)
                    return
                }

                if let result = result {
                    self?.recognizedText = result.bestTranscription.formattedString
                    print("Recognized text: \(self?.recognizedText ?? "")")
                }
            }

            do {
                try audioEngine.start()
                isProcessing = true
                print("Audio engine started successfully")
            } catch {
                print("Couldn't start audio engine: \(error.localizedDescription)")
                stopAndReturnResult(command: command)
            }
        } catch {
            print("Audio session configuration failed: \(error.localizedDescription)")
            // Optionally, you can call a Cordova callback here to notify the JavaScript side
        }
    }

    @objc(stopListening:)
    func stopListening(command: CDVInvokedUrlCommand) {
        stopAndReturnResult(command: command)
    }

    private func stopAndReturnResult(command: CDVInvokedUrlCommand) {
        recognitionTask?.cancel()
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? audioSession?.setActive(false)
        
        // Set the audio session back to playback
        do {
            try audioSession?.setCategory(.playback, mode: .default, options: .duckOthers)
            try audioSession?.setActive(true)
            print("Audio session category set to playback")
        } catch {
            print("Error setting audio session category to playback: \(error.localizedDescription)")
        }

        audioSession = nil
        
        isProcessing = false
        
        recognitionRequest = nil
        recognitionTask = nil
        speechRecognizer = nil
        
        // Send the final recognized text back to JavaScript
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: recognizedText)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(speak:)
    func speak(command: CDVInvokedUrlCommand) {
        guard let sentence = command.arguments[0] as? String else {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid argument")
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            return
        }

        // Reset and configure audio session for playback
        resetAndConfigureAudioSessionForPlayback()

        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        CdvAiVoice.speechSynthesizer.delegate = self  // Set delegate to handle completion and errors
        CdvAiVoice.speechSynthesizer.speak(utterance)
    }

    private func resetAndConfigureAudioSessionForPlayback() {
        // Reset and configure the audio session for playback
        do {
            try audioSession?.setCategory(.playback, mode: .default, options: .duckOthers)
            try audioSession?.setActive(true)
            print("Audio session category set to playback for speech synthesis")
        } catch {
            print("Error setting audio session category for playback: \(error.localizedDescription)")
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Speech finished successfully")
        // Handle successful completion if needed
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Speech was cancelled")
        // Handle cancellation if needed
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Speech started")
        // Handle speech start if needed
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("Speech paused")
        // Handle speech pause if needed
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("Speech continued")
        // Handle speech continue if needed
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFail error: Error) {
        print("Speech failed with error: \(error.localizedDescription)")
        // Handle speech failure if needed
    }

    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            print("✅ Available")
        } else {
            print("🔴 Unavailable")
            recognizedText = "Text recognition unavailable. Sorry!"
            stopAndReturnResult(command: CDVInvokedUrlCommand()) // Handle unavailable state
        }
    }
}
