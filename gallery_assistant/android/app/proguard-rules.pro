# MediaPipe protobuf classes - keep them from being removed by R8
-keep class com.google.mediapipe.proto.** { *; }
-keep class com.google.mediapipe.framework.** { *; }
-keepclassmembers class com.google.mediapipe.** {
    *** *(...);
}

# Google Play Core Library
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# LiteRT/TensorFlow Lite
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# Google AI
-keep class com.google.ai.** { *; }
-keep class com.google.gemma.** { *; }
-dontwarn com.google.ai.**
-dontwarn com.google.gemma.**

# Flutter plugins
-keep class io.flutter.** { *; }
-keep class androidx.** { *; }

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
