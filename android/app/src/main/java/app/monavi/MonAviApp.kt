package app.monavi

import android.app.Application
import app.monavi.data.Backend

class MonAviApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Crea el cliente al arrancar para recuperar la sesión guardada.
        Backend.client
    }
}
