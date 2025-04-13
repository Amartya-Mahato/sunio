package com.sunio.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Binder
import android.graphics.Color
import androidx.core.app.NotificationCompat
import android.util.Log
import android.content.pm.ServiceInfo

class MediaProjectionService : Service() {
    companion object {
        private const val TAG = "MediaProjectionService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "media_projection_channel"
        
        // Token data from projection permission
        var PROJECTION_RESULT_CODE = 0
        var PROJECTION_DATA: Intent? = null
    }
    
    private val binder = LocalBinder()
    private var mediaProjection: MediaProjection? = null
    private var isMediaProjectionStarted = false
    
    inner class LocalBinder : Binder() {
        fun getService(): MediaProjectionService = this@MediaProjectionService
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "MediaProjectionService created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand received")
        
        // Start as a foreground service with microphone type only
        val notification = createNotification()
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Important: Only use FOREGROUND_SERVICE_TYPE_MICROPHONE initially
                // We can only use media projection type after getting user consent
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
                Log.d(TAG, "Foreground service started with microphone type")
            } else {
                startForeground(NOTIFICATION_ID, notification)
                Log.d(TAG, "Foreground service started (pre-Q)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground: ${e.message}")
            e.printStackTrace()
        }
        
        // Check if we should initialize media projection
        if (PROJECTION_RESULT_CODE != 0 && PROJECTION_DATA != null && !isMediaProjectionStarted) {
            initializeMediaProjection()
        }
        
        return START_STICKY
    }
    
    // This should be called after user grants permission
    fun initializeMediaProjection() {
        if (PROJECTION_RESULT_CODE == 0 || PROJECTION_DATA == null) {
            Log.e(TAG, "Cannot initialize media projection - no permission data")
            return
        }
        
        try {
            Log.d(TAG, "Initializing media projection")
            
            // CRITICAL: Update the foreground service type to include MEDIA_PROJECTION before getting projection
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    // Create notification again
                    val notification = createNotification()
                    
                    // Update foreground service type to include both microphone and media projection
                    // Using the official Android constants from ServiceInfo
                    startForeground(NOTIFICATION_ID, notification, 
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
                    Log.d(TAG, "Updated foreground service type to include MEDIA_PROJECTION")
                } catch (e: Exception) {
                    Log.e(TAG, "Error updating foreground service type: ${e.message}")
                    e.printStackTrace()
                }
            }
            
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            
            try {
                // Get media projection with explicit SecurityException handling
                mediaProjection = projectionManager.getMediaProjection(PROJECTION_RESULT_CODE, PROJECTION_DATA!!)
                
                if (mediaProjection != null) {
                    Log.d(TAG, "Media projection successfully initialized")
                    isMediaProjectionStarted = true
                } else {
                    Log.e(TAG, "Failed to get media projection (null return)")
                }
            } catch (se: SecurityException) {
                // Handle security exception separately
                Log.e(TAG, "SecurityException getting media projection: ${se.message}")
                // Don't rethrow - allow service to continue running
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing media projection: ${e.message}")
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "MediaProjectionService being destroyed")
        mediaProjection?.stop()
        mediaProjection = null
        isMediaProjectionStarted = false
        PROJECTION_RESULT_CODE = 0
        PROJECTION_DATA = null
        super.onDestroy()
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

    private fun createNotification(): Notification {
        // Create a pending intent that will open the app when tapped
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        // Build the notification
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Broadcasting Audio")
            .setContentText("Your device's audio is being broadcast")
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            
        return builder.build()
    }
} 