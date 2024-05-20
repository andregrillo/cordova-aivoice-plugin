var exec = require('cordova/exec');

exports.coolMethod = function (success, error, arg0) {
    exec(success, error, 'CdvAiVoice', 'coolMethod', [arg0]);
};
