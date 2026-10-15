package io.github.opensourceforfreedom.kotlinactions

/** A single step in a workflow, modelled loosely on a GitHub Actions step. */
data class Step(val name: String, val run: () -> Boolean)

/** What happened when a [Step] was run. */
enum class StepStatus(val icon: String) {
    SUCCESS("✅"),
    FAILURE("❌"),
    SKIPPED("⏭️"),
}

/** The outcome of one [Step]. */
data class StepResult(val name: String, val status: StepStatus)
