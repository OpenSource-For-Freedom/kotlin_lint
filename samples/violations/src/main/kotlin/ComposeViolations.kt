// Deliberate Jetpack Compose mistakes: the compose-rules ruleset must report these.
package violations

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState

// No Modifier parameter on a public composable that emits UI.
@Composable
fun Greeting(name: String) {
    Text(text = "Hello $name")
}

// Mutable state passed in as a parameter instead of value + callback.
@Composable
fun Counter(count: MutableState<Int>) {
    Text(text = "Count ${count.value}")
}

// A Unit-returning composable must be PascalCase.
@Composable
fun badge(label: String) {
    Text(text = label)
}
