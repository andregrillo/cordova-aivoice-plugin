var exec = require('cordova/exec');

exports.startListening = function (success, error) {
    exec(success, error, 'CdvAiVoice', 'startListening');
};

exports.stopListening = function (success, error) {
    exec(success, error, 'CdvAiVoice', 'stopListening');
};

exports.speak = function (success, error, text) {
    exec(success, error, 'CdvAiVoice', 'speak', [text]);
};