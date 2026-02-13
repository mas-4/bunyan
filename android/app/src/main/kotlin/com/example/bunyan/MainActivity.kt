package com.example.bunyan

import android.app.backup.BackupManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.bunyan/backup")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestBackup") {
                    BackupManager.dataChanged("com.example.bunyan")
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
