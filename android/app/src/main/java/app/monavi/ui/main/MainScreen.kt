package app.monavi.ui.main

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DonutLarge
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Savings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import app.monavi.ui.budgets.BudgetsScreen
import app.monavi.ui.settings.SettingsScreen
import app.monavi.ui.summary.SummaryScreen
import app.monavi.ui.theme.Brand
import app.monavi.ui.today.TodayScreen

private data class Tab(val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("Hoy", Icons.Filled.Home),
    Tab("Resumen", Icons.Filled.DonutLarge),
    Tab("Presupuestos", Icons.Filled.Savings),
    Tab("Ajustes", Icons.Filled.Settings),
)

@Composable
fun MainScreen() {
    var selected by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        containerColor = Brand.background,
        bottomBar = {
            NavigationBar(containerColor = Brand.card) {
                tabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selected == index,
                        onClick = { selected = index },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Brand.primaryDark,
                            selectedTextColor = Brand.primaryDark,
                            indicatorColor = Brand.mint,
                        ),
                    )
                }
            }
        },
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when (selected) {
                0 -> TodayScreen()
                1 -> SummaryScreen()
                2 -> BudgetsScreen()
                else -> SettingsScreen()
            }
        }
    }
}
