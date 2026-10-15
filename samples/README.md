# Samples

Fixture projects used by the self-test (`scripts/selftest.sh`), linted with the Android defaults
(`.editorconfig` + `config/detekt.yml` + Jetpack Compose rules).

| Sample | Expectation |
|---|---|
| `android_app/` | A small Jetpack Compose notes app: Activity, ViewModel with `StateFlow`, Compose screen, `@Preview`, Material 3 theme, `build.gradle.kts`. Must lint with **zero** findings. This proves the defaults give no false positives on idiomatic Android code. |
| `kotlin_actions/` | A small plain-Kotlin app (a toy GitHub-Actions-style step runner). Must lint with **zero** findings. |
| `violations/` | Deliberately bad code, including Compose mistakes. Must produce findings from **every** engine (ktlint, compose-rules, detekt). This proves each engine really ran, rather than reporting nothing. |

The samples are only linted, never built, so no Android SDK is needed.
`violations/` must stay excluded from any repo-wide lint of this project's own sources.
