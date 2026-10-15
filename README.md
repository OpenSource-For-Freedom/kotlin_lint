# kotlin_lint

**One linter for Kotlin Android apps.**

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
- Uses Android Studio's formatting style, so *Reformat Code* and the linter agree
- Checks Jetpack Compose code against the Compose API guidelines
- Prints `file:line:col: message`, which shows up as inline annotations on pull requests
- Fixes formatting automatically with `--fix`
- Pins and checksum-verifies every engine it downloads

It does not replace **Android Lint**. Keep running `./gradlew lint` for Android-specific checks
(manifest, resources, API levels).

## Status

> **Early development.** The Android defaults and the self-test below work today.
> The `kotlin-lint` command and the GitHub Action are being built. See the
> [build plan](docs/BUILD_PLAN.md). Sections marked *planned* show how they will work.

## Use it locally

**Planned:**

```console
kotlin-lint            # lint the current project
kotlin-lint --fix      # fix formatting
```

**Today:** copy [`.editorconfig`](.editorconfig) and [`config/detekt.yml`](config/detekt.yml) into your
Android project root. Then run ktlint and detekt with them (needs Java 17+):

```console
ktlint "**/*.kt" "**/*.kts"
detekt --config config/detekt.yml --build-upon-default-config
```

For the Compose checks, add the [compose-rules](https://mrmans0n.github.io/compose-rules/) ktlint
ruleset to your ktlint setup. Android Studio reads the same `.editorconfig`, so the editor and the
linter agree.

## Use it in GitHub Actions

**Planned:**

```yaml
# .github/workflows/lint.yml
name: Lint
on: [push, pull_request]

jobs:
  kotlin-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: opensource-for-freedom/kotlin_lint@v1
```

Problems appear as annotations on the pull request, and the job fails if any are found.
This doesn't need a Gradle build or the Android SDK, so it is much faster than a full Android build.

## Try it: the self-test

One command checks every scan feature and writes a Markdown report:

```console
./scripts/selftest.sh   # needs bash, curl and a JDK 17+; writes selftest-report.md
```

| Part | What it proves |
|---|---|
| Samples | A Jetpack Compose app (`samples/android_app`) and a plain Kotlin app lint clean. Deliberately bad code (`samples/violations`) is flagged by every engine. |
| Scan features | Each case in `tests/cases/` (ktlint formatting, imports, naming, Compose rules, detekt bugs, complexity and style, the Android defaults, `@Suppress`, `build.gradle.kts`, Kotlin under `src/main/java`) produces **exactly** the findings in its `expected.txt`, down to the rule and line. |
| Fix | `--fix` output matches a reviewed golden file, and only unfixable findings remain. |
| Tooling | A download with the wrong checksum is refused. A linter that produces no report is an error, never a pass. |

CI runs the same script on Linux, macOS and Windows and shows the report in the job summary.
After an intended rule change, `UPDATE_EXPECTED=1 ./scripts/selftest.sh` rewrites the
`expected.txt` files. Review that diff before committing.
