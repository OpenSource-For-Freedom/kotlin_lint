package io.github.opensourceforfreedom.kotlinactions

/**
 * Runs steps in order. As in GitHub Actions, once a step fails every later step is skipped.
 */
class Workflow(private val name: String, private val steps: List<Step>) {
    fun run(): List<StepResult> {
        var failed = false
        return steps.map { step ->
            val status =
                when {
                    failed -> StepStatus.SKIPPED
                    step.run() -> StepStatus.SUCCESS
                    else -> StepStatus.FAILURE.also { failed = true }
                }
            StepResult(step.name, status)
        }
    }

    /** Renders results as a Markdown table, the format GitHub job summaries use. */
    fun summary(results: List<StepResult>): String = buildString {
        appendLine("## $name")
        appendLine()
        appendLine("| Step | Status |")
        appendLine("|---|---|")
        results.forEach { appendLine("| ${it.name} | ${it.status.icon} ${it.status} |") }
    }
}
