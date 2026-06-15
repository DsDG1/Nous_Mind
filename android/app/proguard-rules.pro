-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# device_calendar: 4.x's Android implementation uses reflection-style
# access via the plugin's MethodChannel. R8 strips com.builttoroam.* in
# release builds unless explicitly kept, which silently breaks
# retrieveCalendars() and createOrUpdateEvent().
-keep class com.builttoroam.devicecalendar.** { *; }
-keep class com.builttoroam.device_calendar.** { *; }
-keepattributes *Annotation*

# google_mlkit_text_recognition uses reflection / JNI to reach ML Kit
# classes from `com.google.mlkit.vision.text.*` and the bundled Chinese
# model. R8 in release (`isMinifyEnabled = true`) strips them otherwise
# and `TextRecognizer.processImage` throws `NoClassDefFoundError`, which
# the Dart-side catch in `_runOcrWithScript` (`ai_analyzer.dart:568`)
# translates into "截图识别失败". Keep all ML Kit classes and plugin
# classes to match the behaviour we already see in `flutter run` debug.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.vision.interfaces.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# google_mlkit_commons / google_mlkit_text_recognition plugin entry
# points are looked up by Flutter via reflection in release builds.
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-dontwarn com.google_mlkit_commons.**
-dontwarn com.google_mlkit_text_recognition.**
