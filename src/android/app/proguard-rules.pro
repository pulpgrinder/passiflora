# Keep JNI native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep JavascriptInterface bridge methods (accessed by name from JS)
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep the Bridge inner class (referenced by addJavascriptInterface)
-keep class com.example.zipserve.MainActivity$Bridge { *; }

# Keep methods called from native code via JNI reflection
-keepclassmembers class com.example.zipserve.MainActivity {
    void evalJsFromNative(java.lang.String);
}
