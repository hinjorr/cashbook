# Plugins such as shared_preferences_android call their Kotlin code from Dart
# through JNI, looking methods up by name and signature. R8 can't see those
# calls, so without these rules it renames or removes the methods and the app
# fails on startup with NoSuchMethodError.
-keep class io.flutter.plugins.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class kotlin.coroutines.Continuation { *; }
