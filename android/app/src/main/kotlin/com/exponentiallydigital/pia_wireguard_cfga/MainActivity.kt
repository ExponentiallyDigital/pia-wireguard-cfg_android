package com.exponentiallydigital.pia_wireguard_cfga

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    // [CHANGE 5] FLAG_SECURE blocks:
    //   - System screenshot APIs (adb shell screencap, power+volume buttons)
    //   - Android Recent Apps / Task Switcher thumbnail capture
    //     (the preview renders as a blank/black frame instead of live content)
    //   - Screen recording tools that use the MediaProjection API
    //
    // Must be applied in onCreate() BEFORE super.onCreate() renders any Flutter
    // surface, otherwise the first frame may briefly appear unprotected.
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
