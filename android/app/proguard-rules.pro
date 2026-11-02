# Release-build rules for Cue.
#
# ML Kit's text recognition library contains code paths for Chinese, Japanese,
# Korean and Devanagari script recognisers. Those live in separate Gradle
# dependencies that this app deliberately does not include (it only reads
# Latin script, which is bundled).
#
# In a release build R8 sees the references, cannot find the classes, and
# fails the whole build. These rules tell R8 the missing classes are expected.

-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep the ML Kit entry points that are reached through reflection from the
# Flutter plugin, so R8 does not strip them.
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
