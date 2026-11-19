package com.school365ai.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity, not a plain one: the app lock's fingerprint and face
// prompt (local_auth, docs/mobile-apps-review.md 4.4) is a fragment.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Payslips and the passcode screens ask for this while they are open
        // (lib/core/widgets/secure_screen.dart): no screenshots, no screen
        // recording, and a blank card in the recent-apps view. Everywhere
        // else screenshots stay allowed - staff use them to ask for help.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "school365ai/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // A running trip's sheet asks for this while it is open
        // (lib/features/my_trip/presentation/widgets/trip_screen_hold.dart):
        // the screen stays on in the cradle. Android drops it by itself when
        // the phone is locked or the app is put away.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "school365ai/keep_awake")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepAwake" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
