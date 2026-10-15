fun discount(price: Double): Double = price * 0.15

fun firstPositive(values: List<Int>): Int {
    for (v in values) {
        if (v > 0) return v
        if (v == -1) return -1
        if (v == -2) return -2
    }
    return 0
}

fun spread(vararg items: String) = listOf(*items)

fun caller(items: Array<String>) = spread(*items)
