import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview

@Composable
fun Title(text: String) {
    Text(text = text)
}

@Composable
fun Counter(count: MutableState<Int>, modifier: Modifier = Modifier) {
    Text(text = "${count.value}", modifier = modifier)
}

@Composable
fun badge(label: String, modifier: Modifier = Modifier) {
    Text(text = label, modifier = modifier)
}

@Composable
fun Toggle(modifier: Modifier = Modifier) {
    val on = mutableStateOf(false)
    Text(text = "${on.value}", modifier = modifier)
}

@Composable
fun Header(modifier: Modifier = Modifier, title: String) {
    Text(text = title, modifier = modifier)
}

@Composable
fun ProfileScreen(viewModel: ProfileViewModel, modifier: Modifier = Modifier) {
    ProfileBody(viewModel = viewModel, modifier = modifier)
}

@Composable
fun ProfileBody(viewModel: ProfileViewModel, modifier: Modifier = Modifier) {
    Text(text = viewModel.toString(), modifier = modifier)
}

@Composable
fun TwoThings(modifier: Modifier = Modifier) {
    Text(text = "one", modifier = modifier)
    Text(text = "two")
}

@Preview
@Composable
fun PublicPreview() {
    Title(text = "x")
}
