// The Android relaxations are scoped to @Composable / @Preview. Ordinary code is still checked.

class Repository {
    fun timeoutMillis(): Long = 30000

    fun save(id: Long, name: String, email: String, phone: String, city: String, country: String) {
        println("$id $name $email $phone $city $country")
    }

    private fun helperNobodyCalls() = Unit
}

fun FormatPrice(cents: Long): String = "$" + cents / 100
