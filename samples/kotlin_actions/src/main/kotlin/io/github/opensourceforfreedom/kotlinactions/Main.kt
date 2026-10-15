package io.github.opensourceforfreedom.kotlinactions

fun main() {
    val workflow =
        Workflow(
            name = "kotlin_actions demo",
            steps =
                listOf(
                    Step("checkout") { true },
                    Step("build") { true },
                    Step("test") { true },
                ),
        )
    print(workflow.summary(workflow.run()))
}
