import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

// Each line below used to be a false positive for Android code. With the defaults: no findings.

val Teal200 = Color(0xFF03DAC5)

data class Profile(val name: String, val city: String)

@Composable
fun HomeScreen(
    title: String,
    subtitle: String,
    footer: String,
    showHeader: Boolean,
    showFooter: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(16.dp)) {
        if (showHeader) Text(text = title)
        Text(text = subtitle, modifier = Modifier.padding(top = 8.dp, bottom = 12.dp))
        if (showFooter) Text(text = footer, color = Color(0xFF888888))
        Button(onClick = onClick) { Text(text = "OK") }
    }
}

@Preview(showBackground = true, widthDp = 360)
@Composable
private fun HomeScreenPreview() {
    HomeScreen(
        title = "Hi",
        subtitle = "There",
        footer = "Bye",
        showHeader = true,
        showFooter = false,
        onClick = {},
    )
}
