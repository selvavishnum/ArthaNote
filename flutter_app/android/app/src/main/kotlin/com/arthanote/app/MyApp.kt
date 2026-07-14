package com.arthanote.app

import android.app.Application
import android.util.Log
import com.facebook.FacebookSdk
import com.facebook.appevents.AppEventsLogger

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Facebook SDK v13+ refuses to flush events without a client token
        // (App Dashboard → Settings → Advanced → Security → Client token).
        // Gate the whole init on it so an unset token can never crash the
        // app in the field — it just means no FB events until it's filled.
        val clientToken = getString(R.string.facebook_client_token)
        if (clientToken.isNotBlank()) {
            try {
                FacebookSdk.setClientToken(clientToken)
                FacebookSdk.setAutoInitEnabled(true)
                FacebookSdk.fullyInitialize()
                FacebookSdk.setAutoLogAppEventsEnabled(true)
                // Fires the install / "Activate App" event FB Ads attribution needs
                AppEventsLogger.activateApp(this)
            } catch (t: Throwable) {
                Log.w("ArthaNote", "Facebook SDK init failed", t)
            }
        }
    }
}
