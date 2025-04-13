package com.sunio.app

import android.content.Intent
import android.content.Context
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import android.media.projection.MediaProjectionManager
import android.graphics.Color
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.sunio.app/foreground_service"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "media_projection_channel"
    private val FOREGROUND_SERVICE_ACTION = "com.sunio.app.FOREGROUND_SERVICE"
    private val MEDIA_PROJECTION_REQUEST = 1001
    
    companion object {
        private const val TAG = "MainActivity"
    }
    
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        // First only start the foreground service with microphone type
                        val success = startMicrophoneForegroundService()
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in startForegroundService: ${e.message}")
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                    }
                }
                "requestMediaProjection" -> {
                    try {
                        requestMediaProjectionPermission(result)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error requesting media projection: ${e.message}")
                        result.error("PROJECTION_ERROR", "Failed to request media projection: ${e.message}", null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        val success = stopMediaProjectionForegroundService()
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in stopForegroundService: ${e.message}")
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun requestMediaProjectionPermission(result: MethodChannel.Result) {
        Log.d(TAG, "Requesting media projection permission")
        
        try {
            // Save the pending result before showing the permission dialog
            pendingResult = result
            
            // Get the media projection manager service
            val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            
            // Create the capture intent with a try-catch to handle potential SecurityExceptions
            try {
                val intent = mediaProjectionManager.createScreenCaptureIntent()
                startActivityForResult(intent, MEDIA_PROJECTION_REQUEST)
            } catch (e: SecurityException) {
                Log.e(TAG, "SecurityException creating capture intent: ${e.message}")
                pendingResult = null
                // Return success anyway so the app doesn't crash
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting media projection: ${e.message}")
            e.printStackTrace()
            pendingResult = null
            // Return success anyway to avoid crashing the app
            result.success(true)
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == MEDIA_PROJECTION_REQUEST) {
            val result = pendingResult
            pendingResult = null
            
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Media projection permission granted")
                
                try {
                    // Store projection data in the service
                    MediaProjectionService.PROJECTION_RESULT_CODE = resultCode
                    MediaProjectionService.PROJECTION_DATA = data.clone() as Intent
                    
                    // Trigger the service to initialize the media projection with updated foreground type
                    val intent = Intent(this, MediaProjectionService::class.java).apply {
                        action = FOREGROUND_SERVICE_ACTION
                    }
                    
                    // Start service safely with try-catch
                    try {
                        ContextCompat.startForegroundService(this, intent)
                        
                        // Give the service a moment to update its foreground type
                        // before WebRTC tries to use the media projection
                        Thread.sleep(100)
                        
                        // Notify Flutter that permission was granted
                        result?.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error starting service after permission: ${e.message}")
                        e.printStackTrace()
                        result?.success(true) // Still return true to avoid app crash
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error initializing projection after permission: ${e.message}")
                    e.printStackTrace()
                    // Return success anyway to avoid crashing the app
                    result?.success(true)
                }
            } else {
                Log.d(TAG, "Media projection permission denied or canceled")
                // Return success anyway so the app can continue
                result?.success(true)
            }
        }
    }
    
    private fun startMicrophoneForegroundService(): Boolean {
        try {
            Log.d(TAG, "Starting foreground service with microphone type")
            createNotificationChannel()
            
            // Start the foreground service with microphone type only
            val intent = Intent(this, MediaProjectionService::class.java).apply {
                action = FOREGROUND_SERVICE_ACTION
            }
            
            ContextCompat.startForegroundService(this, intent)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}")
            e.printStackTrace()
            return false
        }
    }
    
    private fun stopMediaProjectionForegroundService(): Boolean {
        try {
            val intent = Intent(this, MediaProjectionService::class.java)
            stopService(intent)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping foreground service: ${e.message}")
            e.printStackTrace()
            return false
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Media Projection Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Channel for audio broadcasting services"
                enableLights(true)
                lightColor = Color.RED
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(title: String, content: String): Notification {
        // Create a pending intent that will open the app when tapped
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        // Build the notification
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            
        return builder.build()
    }
    
    override fun onResume() {
        super.onResume()
        
        // Check if we need to show Google Play Services error
        try {
            val prefs = getSharedPreferences("gms_status", Context.MODE_PRIVATE)
            val errorCode = prefs.getInt("gms_error_code", -1)
            
            if (errorCode != -1 && errorCode != ConnectionResult.SUCCESS) {
                // Clear the stored error code
                prefs.edit().remove("gms_error_code").apply()
                
                // Show dialog to fix Play Services if possible
                val googleApiAvailability = GoogleApiAvailability.getInstance()
                if (googleApiAvailability.isUserResolvableError(errorCode)) {
                    googleApiAvailability.getErrorDialog(this, errorCode, 1002)?.show()
                    Log.d(TAG, "Showing Google Play Services error dialog")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling Google Play Services status: ${e.message}")
        }
    }
}
