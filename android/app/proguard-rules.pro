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
