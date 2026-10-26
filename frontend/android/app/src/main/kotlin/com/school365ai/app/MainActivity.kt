package com.school365ai.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
