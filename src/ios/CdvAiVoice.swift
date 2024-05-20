import Foundation
import AVFoundation
import Speech

@objc(CdvAiVoice) class CdvAiVoice: CDVPlugin {
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @objc(speak:)
    func speak(command: CDVInvokedUrlCommand) {
        guard let text = command.arguments[0] as? String else {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid argument")
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            return
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        speechSynthesizer.speak(utterance)
        
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Speaking")
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc(startListening:)
    func startListening(command: CDVInvokedUrlCommand) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                self.startRecording(command: command)
            default:
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Speech recognition not authorized")
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    private func startRecording(command: CDVInvokedUrlCommand) {
        speechRecognizer = SFSpeechRecognizer()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Unable to create request")
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recognitionFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recognitionFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.sendToOpenAI(text: text) { apiResult in
                    switch apiResult {
                    case .success(let json):
                        let action = json["action"] as? String ?? ""
                        let toSpeak = json["toSpeak"] as? String ?? ""
                        let valid = json["valid"] as? Bool ?? false
                        
                        let response: [String: Any] = [
                            "action": action,
                            "toSpeak": toSpeak,
                            "valid": valid
                        ]
                        
                        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
                        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                    case .failure(let error):
                        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error.localizedDescription)
                        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                    }
                }
            } else if let error = error {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error.localizedDescription)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    
    @objc(stopListening:)
    func stopListening(command: CDVInvokedUrlCommand) {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Stopped listening")
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    private func sendToOpenAI(text: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    let apiKey = "your_openai_api_key"
    let url = URL(string: "https://api.openai.com/v1/your-endpoint")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let parameters: [String: Any] = [
        "model": "gpt-3.5-turbo",
        "prompt": text,
        "max_tokens": 1000,
        "temperature": 0.7
    ]
    
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
    } catch {
        completion(.failure(error))
        return
    }
    
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        
        guard let data = data else {
            let error = NSError(domain: "com.yourplugin.error", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"])
            completion(.failure(error))
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                completion(.success(json))
            } else {
                let error = NSError(domain: "com.yourplugin.error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
                completion(.failure(error))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    task.resume()
}

}
