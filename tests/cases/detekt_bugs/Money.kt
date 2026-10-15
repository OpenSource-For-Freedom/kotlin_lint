class Money(val cents: Long) {
    override fun equals(other: Any?): Boolean = other is Money && other.cents == cents
}

fun load(path: String): String {
    try {
        return java.io.File(path).readText()
    } catch (e: Exception) {
        return ""
    }
}

fun empty() {
}

// Not reported by the CLI today: these detekt rules need type resolution (the compile
// classpath), which the Gradle plugin will provide (build plan, Phase 4). expected.txt
// records that; when type resolution lands, they move into expected.txt.
fun length(text: String?): Int = text!!.length

fun unreachable(): Int {
    return 1
    println("never")
}

suspend fun blocking(): String {
    Thread.sleep(SLEEP_MILLIS)
    return "done"
}

private const val SLEEP_MILLIS = 100L
