package app.monavi.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Colores de marca de MonAvi (los mismos de iPhone). */
object Brand {
    val primary = Color(0xFF00A585)
    val primaryDark = Color(0xFF027A64)
    val darkSurface = Color(0xFF0E1614)
    val onDark = Color(0xFFF2F5F4)
    val alert = Color(0xFFB5453A)
    val accentOnDark = Color(0xFF5FE3C4)
    val border = Color(0xFFE4E9E7)
    val background = Color(0xFFF4F6F5)
    val card = Color(0xFFFFFFFF)
    val secondaryText = Color(0xFF6B7A76)
    val mint = Color(0xFFE8F6F2)
}

private val colors = lightColorScheme(
    primary = Brand.primary,
    onPrimary = Color.White,
    primaryContainer = Brand.mint,
    onPrimaryContainer = Brand.primaryDark,
    secondary = Brand.primaryDark,
    background = Brand.background,
    surface = Brand.card,
    surfaceVariant = Color(0xFFEDF1EF),
    onSurfaceVariant = Brand.secondaryText,
    error = Brand.alert,
    outline = Brand.border,
)

private val typography = Typography(
    headlineLarge = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.4).sp),
    titleLarge = TextStyle(fontSize = 21.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp),
    bodyMedium = TextStyle(fontSize = 14.sp),
    labelLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
)

@Composable
fun MonAviTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, typography = typography, content = content)
}
