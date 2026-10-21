# JS 桥接类不能混淆，否则 addJavascriptInterface 注入的方法名会变
-keep class com.qingzhangmao.app.StoreBridge { *; }
-keepclassmembers class com.qingzhangmao.app.StoreBridge {
    public *;
}

# WebView 里的 JS 接口回调
-keepattributes JavascriptInterface
-keepattributes *Annotation*
