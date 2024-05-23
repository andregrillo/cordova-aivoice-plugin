var exec = require('cordova/exec');

exports.startListening = function (success, error, autoStopRecording) {
    exec(success, error, 'CdvAiVoice', 'startListening', [autoStopRecording]);
};

exports.stopListening = function (success, error) {
    exec(success, error, 'CdvAiVoice', 'stopListening');
};

exports.speak = function (success, error, text) {
    exec(success, error, 'CdvAiVoice', 'speak', [text]);
};
    
exports.testSpeak = function (success, error, text) {
    exec(success, error, 'CdvAiVoice', 'testSpeak', [text]);
};