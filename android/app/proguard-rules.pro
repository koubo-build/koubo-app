# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# SharedPreferences Pigeon generated code
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Play Core (missing in release build, safe to ignore)
-dontwarn com.google.android.play.core.**

