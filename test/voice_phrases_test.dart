import 'package:cue/core/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whole sentences people actually say, not only the documented commands.
///
/// The live logs showed that Cue understood its command list and rejected the
/// way a person really asks. This list is the regression net for that: every
/// entry must reach a command, and the test names the one that did not.
const Map<String, VoiceCommand> _phrases = <String, VoiceCommand>{
  // Asking for a reading.
  'read this': VoiceCommand.readNow,
  'read it': VoiceCommand.readNow,
  'please read this page': VoiceCommand.readNow,
  'what does this say': VoiceCommand.readNow,
  'what does that say': VoiceCommand.readNow,
  'can you read it for me': VoiceCommand.readNow,
  'scan this': VoiceCommand.readNow,
  // Navigation.
  'go to the next line': VoiceCommand.nextSentence,
  'go back': VoiceCommand.previousSentence,
  'previous sentence': VoiceCommand.previousSentence,
  'start from the beginning': VoiceCommand.startOver,
  'read it again': VoiceCommand.repeat,
  'repeat that': VoiceCommand.repeat,
  'stop talking': VoiceCommand.stop,
  'hold on a moment': VoiceCommand.pause,
  'continue reading': VoiceCommand.resume,
  'carry on': VoiceCommand.resume,
  // Speed.
  'speak a bit slower': VoiceCommand.slower,
  'too fast': VoiceCommand.slower,
  'speed up please': VoiceCommand.faster,
  // Modes.
  'switch to object mode': VoiceCommand.objectMode,
  'identify objects': VoiceCommand.objectMode,
  'text mode': VoiceCommand.textMode,
  'show me the preview': VoiceCommand.showPreview,
  // Torch.
  'turn on the flashlight': VoiceCommand.torchOn,
  'turn off the light': VoiceCommand.torchOff,
  // Questions and small talk.
  'what time is it': VoiceCommand.currentTime,
  'tell me the time': VoiceCommand.currentTime,
  "what's today's date": VoiceCommand.currentDate,
  'what day is it': VoiceCommand.currentDate,
  'where am i': VoiceCommand.location,
  'what is my location': VoiceCommand.location,
  'what is your name': VoiceCommand.whoAreYou,
  "what's your name": VoiceCommand.whoAreYou,
  'who are you': VoiceCommand.whoAreYou,
  'how are you': VoiceCommand.howAreYou,
  'what can you do': VoiceCommand.help,
  'what is this': VoiceCommand.whatIsThis,
  "what's this": VoiceCommand.whatIsThis,
  'what do you see': VoiceCommand.whatIsThis,
  'thank you': VoiceCommand.thanks,
  'good morning': VoiceCommand.greeting,
  'hello': VoiceCommand.greeting,
  'help me': VoiceCommand.help,
  'change the language': VoiceCommand.toggleLanguage,
  'switch language': VoiceCommand.toggleLanguage,
  'turn on location': VoiceCommand.locationSettings,
  'open location settings': VoiceCommand.locationSettings,
  // State, repair and progress.
  'what mode am i in': VoiceCommand.whatMode,
  'which mode is this': VoiceCommand.whatMode,
  'what language are you using': VoiceCommand.whichLanguage,
  'is the torch on': VoiceCommand.torchState,
  'is the light on': VoiceCommand.torchState,
  'how fast are you reading': VoiceCommand.readingSpeed,
  'battery': VoiceCommand.battery,
  'how much charge is left': VoiceCommand.battery,
  'what did you say': VoiceCommand.repeatAnswer,
  'what did you just say': VoiceCommand.repeatAnswer,
  'never mind': VoiceCommand.neverMind,
  'forget it': VoiceCommand.neverMind,
  'where was i': VoiceCommand.readingProgress,
  'how much is left': VoiceCommand.readingProgress,
  'read from the top': VoiceCommand.startOver,
  // Vision questions.
  'what colour is this': VoiceCommand.questionColour,
  'what color is it': VoiceCommand.questionColour,
  "what's on my left": VoiceCommand.whatIsLeft,
  'what is on my right': VoiceCommand.whatIsRight,
  'anything on the left': VoiceCommand.whatIsLeft,
  // Hindi, as a Hindi recogniser actually returns it.
  'पढ़ो': VoiceCommand.readNow,
  'अगला': VoiceCommand.nextSentence,
  'पिछला': VoiceCommand.previousSentence,
  'दोहराओ': VoiceCommand.repeat,
  'रुको': VoiceCommand.stop,
  'जारी रखो': VoiceCommand.resume,
  'धीरे बोलो': VoiceCommand.slower,
  'तेज़ बोलो': VoiceCommand.faster,
  'समय क्या है': VoiceCommand.currentTime,
  'तारीख क्या है': VoiceCommand.currentDate,
  'मैं कहाँ हूँ': VoiceCommand.location,
  'तुम्हारा नाम क्या है': VoiceCommand.whoAreYou,
  'यह क्या है': VoiceCommand.whatIsThis,
  'भाषा बदलो': VoiceCommand.toggleLanguage,
  'नमस्ते': VoiceCommand.greeting,
  'धन्यवाद': VoiceCommand.thanks,
  'कौन सा मोड है': VoiceCommand.whatMode,
  'कौन सी भाषा है': VoiceCommand.whichLanguage,
  'टॉर्च चालू है': VoiceCommand.torchState,
  'कितनी तेज़ है': VoiceCommand.readingSpeed,
  'बैटरी': VoiceCommand.battery,
  'क्या कहा': VoiceCommand.repeatAnswer,
  'कुछ नहीं': VoiceCommand.neverMind,
  'कहाँ था': VoiceCommand.readingProgress,
  'कितना बाकी है': VoiceCommand.readingProgress,
  'रंग क्या है': VoiceCommand.questionColour,
  'मेरी बाईं ओर क्या है': VoiceCommand.whatIsLeft,
  'मेरी दाईं ओर क्या है': VoiceCommand.whatIsRight,
};

void main() {
  group('real sentences', () {
    _phrases.forEach((phrase, expected) {
      test('"$phrase"', () {
        expect(parseVoiceCommand(phrase), expected);
      });
    });
  });
}
