package app.monavi.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.monavi.data.Backend
import app.monavi.data.Repo
import app.monavi.ui.auth.AuthScreen
import app.monavi.ui.main.MainScreen
import app.monavi.ui.onboarding.OnboardingScreen
import app.monavi.ui.theme.Brand
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus

/** Sin sesión -> Entrar; sesión sin onboarding -> Onboarding; si no, la app. */
@Composable
fun AppRoot() {
    val status by Backend.client.auth.sessionStatus.collectAsState()
    when (val s = status) {
        is SessionStatus.Initializing -> Loading()
        is SessionStatus.NotAuthenticated, is SessionStatus.RefreshFailure -> AuthScreen()
        is SessionStatus.Authenticated -> SignedIn(s.session.user?.id ?: "")
    }
}

@Composable
private fun SignedIn(userId: String) {
    var onboarded by remember(userId) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(userId) {
        onboarded = runCatching { Repo.profile()?.onboardingCompletedAt != null }.getOrDefault(true)
    }
    when (onboarded) {
        null -> Loading()
        false -> OnboardingScreen(onDone = { onboarded = true })
        true -> MainScreen()
    }
}

@Composable
fun Loading() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = Brand.primary)
    }
}
