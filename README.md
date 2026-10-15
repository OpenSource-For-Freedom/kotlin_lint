# kotlin_lint

<p align="center">
  <img src="assets/logo.svg" alt="kotlin-lint: the Android robot. ktlint + detekt + Compose rules for Android. Same system, new rules.">
</p>

**One linter for Kotlin Android apps that runs the same on your laptop and in GitHub Actions.**

## What it is

`kotlin-lint` bundles three proven Kotlin linters behind one command, with defaults made for Android:

- **ktlint**: formatting and style, set to Android Studio's style
- **detekt**: code smells, complexity and likely bugs
- **Jetpack Compose rules**: Compose mistakes, such as a missing `Modifier` parameter or a `MutableState` passed as a parameter

## Why

Android teams usually wire ktlint, detekt and Compose rules together by hand, then fight false positives:

- `@Composable fun NotesScreen` flagged for its capital letter
- `16.dp` flagged as a magic number
- `@Preview` functions flagged as unused
- the linter disagreeing with Android Studio's *Reformat Code*

`kotlin-lint` ships defaults that already handle all of that. It runs the same way everywhere, like
`actionlint` or `pylint`: same command, same config, same results locally and in CI.

## What it does

- Lints every `*.kt` and `*.kts` file, including Kotlin under `src/main/java` and your `build.gradle.kts` files
- Skips `build/` and `generated/` folders
- Uses Android Studio's formatting style, so *Reformat Code* and the linter agree
- Checks Jetpack Compose code against the Compose API guidelines
- Prints `file:line:col: message [rule]` and exits `1` when it finds problems, so CI fails the build
- Fixes formatting automatically with `kotlin-lint fix`
- Pins and checksum-verifies every engine it downloads

It does not replace **Android Lint**. Keep running `./gradlew lint` for Android-specific checks
(manifest, resources, API levels).

## Use it locally

You need `bash`, `curl` and a JDK 17+. On Windows, use Git Bash.

```console
git clone https://github.com/opensource-for-freedom/kotlin_lint.git
cd your-android-app
../kotlin_lint/bin/kotlin-lint            # logo + menu
../kotlin_lint/bin/kotlin-lint lint       # check the current project
../kotlin_lint/bin/kotlin-lint fix        # auto-format, then show what is left
```

Running it with no command in a terminal opens the menu:

<p align="center">
  <img src="assets/menu.svg" alt="kotlin-lint menu: 1 Lint, 2 Fix, 3 Self-test, 4 Version, 5 Help, q Quit">
</p>

The output points straight at the problem (from `kotlin-lint lint samples/violations`):

```text
samples/violations/src/main/kotlin/ComposeViolations.kt:10:5: This @Composable function emits content but doesn't have a modifier parameter. [compose:modifier-missing-check]
samples/violations/src/main/kotlin/Violations.kt:9:1: Unexpected indentation (2) (should be 4) [standard:indent]
samples/violations/src/main/kotlin/Violations.kt:11:14: This expression contains a magic number. Consider defining it to a well named constant. [detekt:MagicNumber]
...

31 problem(s) (ktlint 17, compose-rules 5, detekt 9)
```

Your project's own `.editorconfig` wins for any setting it defines. Anything it leaves out comes
from the Android defaults in [`.editorconfig`](.editorconfig) and [`config/detekt.yml`](config/detekt.yml).

## Use it in GitHub Actions

Add this workflow to your Android app:

```yaml
# .github/workflows/kotlin-lint.yml
name: Kotlin lint
on: [push, pull_request]

jobs:
  kotlin-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v6
        with:
          distribution: temurin
          java-version: "17"
      - name: Lint Kotlin
        run: |
          git clone --depth 1 https://github.com/opensource-for-freedom/kotlin_lint.git "$RUNNER_TEMP/kotlin_lint"
          "$RUNNER_TEMP/kotlin_lint/bin/kotlin-lint" lint
```

The job fails when problems are found, and the log lists each one as `file:line:col`.
This doesn't need a Gradle build or the Android SDK, so it is much faster than a full Android build.

*Planned:* a one-line `uses: opensource-for-freedom/kotlin_lint@v1` Action with inline PR
annotations. See the [build plan](docs/BUILD_PLAN.md).

## Try it: the self-test

One command checks every scan feature and writes a Markdown report:

```console
./bin/kotlin-lint selftest   # same as ./scripts/selftest.sh; writes selftest-report.md
```

| Part | What it proves |
|---|---|
| Samples | A Jetpack Compose app (`samples/android_app`) and a plain Kotlin app lint clean. Deliberately bad code (`samples/violations`) is flagged by every engine. |
| Scan features | Each case in `tests/cases/` (ktlint formatting, imports, naming, Compose rules, detekt bugs, complexity and style, the Android defaults, `@Suppress`, `build.gradle.kts`, Kotlin under `src/main/java`) produces **exactly** the findings in its `expected.txt`, down to the rule and line. |
| Fix | `fix` output matches a reviewed golden file, and only unfixable findings remain. |
| Tooling | A download with the wrong checksum is refused. A linter that produces no report is an error, never a pass. |
| Command line | The logo and menu (terminal and this README's images), `lint` and `fix` exit codes and output, `NO_COLOR`, and a project outside this repo. |

CI runs the same script on Linux, macOS and Windows and shows the report in the job summary.
After an intended rule change, `UPDATE_EXPECTED=1 ./scripts/selftest.sh` rewrites the
`expected.txt` files. Review that diff before committing. The README images are rendered
from the CLI's own colored output: after changing `assets/logo.txt` or the menu, run
`python3 scripts/render-logo.py`.
