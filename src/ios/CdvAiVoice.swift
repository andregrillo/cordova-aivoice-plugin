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
    private var callbackId: String?
    private var autoStopRecording: Bool?
    
    var recognizedText: String?
    var isProcessing: Bool = false
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
//    private var silenceDbLevel: Double
    private var silenceEventsCount: Int = 0

    @objc(startListening:)
    func startListening(command: CDVInvokedUrlCommand) {
        if command.arguments.count > 0, let autoStop = command.arguments[0] as? Bool {
            autoStopRecording = autoStop
        } else {
            autoStopRecording = false
        }
        self.callbackId = command.callbackId
        // Request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else {
                print("Microphone permission not granted")
                // You can call a Cordova callback here to notify the JavaScript side
                return
            }

            DispatchQueue.main.async {
                self.configureAudioSessionAndStartRecognition()
            }
        }
    }

    private func configureAudioSessionAndStartRecognition() {
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
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                recognitionRequest.append(buffer)
                if let autoStop = self?.autoStopRecording {
                    if autoStop {
                        self?.checkForSilence(buffer: buffer)
                    }
                }
            }

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                if let error = error {
                    print("Recognition error: \(error.localizedDescription)")
                    self?.stopAndReturnResult()
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
                stopAndReturnResult()
            }
        } catch {
            print("Audio session configuration failed: \(error.localizedDescription)")
            //Cordova callback here to notify the JavaScript side
        }
    }

    private func checkForSilence(buffer: AVAudioPCMBuffer) {
        let channelData = buffer.floatChannelData![0]
        let channelDataValueArray = stride(from: 0,
                                           to: Int(buffer.frameLength),
                                           by: buffer.stride).map { channelData[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)
        
        print("Current dB level: \(avgPower)")

        if avgPower < -50 {
//            if silenceTimer == nil {
                silenceEventsCount += 1
                if silenceEventsCount >= 10 {
                    if let callbackId = self.callbackId {
                        silenceEventsCount = 0
                        stopAndReturnResult()
                    }
                }
        } else {
            silenceEventsCount = 0
                print("🔊 Voice detected")
        }
    }

    @objc private func handleSilenceDetected() {
        print("Silence detected for \(silenceThreshold) seconds")
        silenceTimer?.invalidate()
        silenceTimer = nil
        if isProcessing {
            print("Stopping recording due to silence")
            let command = CDVInvokedUrlCommand()
            stopAndReturnResult()
        }
    }

    @objc(stopListening:)
    func stopListening(command: CDVInvokedUrlCommand) {
        print("✋ stopListening called")
        stopAndReturnResult()
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Stopping recording...")
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    private func stopAndReturnResult() {
        print("stopAndReturnResult called")
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
        self.recognizedText = ""
        self.commandDelegate.send(pluginResult, callbackId: self.callbackId)
        self.callbackId = nil
    }

    @objc(speak:)
    func speak(command: CDVInvokedUrlCommand) {

        self.callbackId = command.callbackId
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

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate.send(pluginResult, callbackId: self.callbackId)
    }
//
//    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
//        print("Speech was cancelled")
//        // Handle cancellation if needed
//    }
//
//    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
//        print("Speech started")
//        // Handle speech start if needed
//    }

//    public func speechSynthesizer(_ synthesizer: AVSpeechUtterance, didPause utterance: AVSpeechUtterance) {
//        print("Speech paused")
//        // Handle speech pause if needed
//    }
//
//    public func speechSynthesizer(_ synthesizer: AVSpeechUtterance, didContinue utterance: AVSpeechUtterance) {
//        print("Speech continued")
//        // Handle speech continue if needed
//    }
//
//    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFail error: Error) {
//        print("Speech failed with error: \(error.localizedDescription)")
//        // Handle speech failure if needed
//    }

    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            print("✅ Available")
        } else {
            print("🔴 Unavailable")
            recognizedText = "Text recognition unavailable. Sorry!"
            stopListening(command: CDVInvokedUrlCommand()) // Handle unavailable state
        }
    }
}
