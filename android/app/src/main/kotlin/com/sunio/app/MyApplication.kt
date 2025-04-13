package com.sunio.app

import androidx.multidex.MultiDexApplication
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult
import android.content.Intent
import android.content.Context
import android.util.Log
import com.google.android.gms.security.ProviderInstaller
import java.security.Security

class MyApplication : MultiDexApplication() {
    companion object {
        private const val TAG = "MyApplication"
    }
    
    override fun onCreate() {
        super.onCreate()

        // Install security provider first (needs to happen before other GMS calls)
        installSecurityProvider()
        
        // Initialize Google Play Services properly
        try {
            val googleApiAvailability = GoogleApiAvailability.getInstance()
            val resultCode = googleApiAvailability.isGooglePlayServicesAvailable(this)
            
            if (resultCode != ConnectionResult.SUCCESS) {
                Log.w(TAG, "Google Play Services not available (code $resultCode)")
                
                // Try to verify if we can resolve the error with an explicit Intent
                // This helps address package visibility issues on Android 11+
                if (googleApiAvailability.isUserResolvableError(resultCode)) {
                    // Instead of showing notification which can cause package visibility issues
                    // we'll just log this for now and allow the app to continue
                    Log.i(TAG, "Google Play Services issue is user resolvable")
                    
                    // Store the fact that we need to show the error next time in MainActivity
                    val prefs = getSharedPreferences("gms_status", Context.MODE_PRIVATE)
                    prefs.edit().putInt("gms_error_code", resultCode).apply()
                }
            } else {
                Log.i(TAG, "Google Play Services available")
            }
        } catch (e: SecurityException) {
            // Handle the specific security exception from Google Play Services
            Log.e(TAG, "Security exception during GMS initialization: ${e.message}")
            // We don't rethrow the exception - app should continue despite GMS issues
        } catch (e: Exception) {
            Log.e(TAG, "Error checking Google Play Services: ${e.message}")
            e.printStackTrace()
        }

        // Initialize secure preferences
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
            EncryptedSharedPreferences.create(
                "secure_prefs",
                masterKeyAlias,
                this,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing secure preferences: ${e.message}")
        }
    }
    
    private fun installSecurityProvider() {
        try {
            // Try to install the latest security provider
            ProviderInstaller.installIfNeeded(this)
            Log.d(TAG, "Security provider installed successfully")
        } catch (e: SecurityException) {
            // This can happen on Android 11+ due to package visibility restrictions
            Log.e(TAG, "Security exception installing provider: ${e.message}")
            
            // Fallback to manual security provider setup
            try {
                Security.insertProviderAt(Security.getProvider("AndroidOpenSSL"), 1)
                Log.d(TAG, "Manually inserted AndroidOpenSSL provider")
            } catch (ex: Exception) {
                Log.e(TAG, "Failed manual security provider setup: ${ex.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error installing security provider: ${e.message}")
        }
    }
}
