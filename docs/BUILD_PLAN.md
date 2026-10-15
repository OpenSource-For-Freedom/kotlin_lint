# kotlin_lint build plan

## Goal

A portable, maintainable Kotlin linter that you run **the same way on a laptop and in CI**,
in the spirit of `actionlint` and `pylint`:

- One command: `kotlin-lint` (lint) and `kotlin-lint --fix` (format).
- Install with one step on Linux, macOS or Windows. A JDK isn't required.
- Zero config to start. A single config file in the repo when you need one.
- Output is plain `file:line:col: message [rule]`, which editors, terminals and GitHub
  problem matchers already understand.
- The GitHub Action is a thin installer around the same binary, never a second implementation.

Under the hood it wraps **ktlint** (style/formatting), **detekt** (smells, complexity,
bugs) and the **Jetpack Compose rules** (`io.nlopez.compose.rules`). Users only ever see `kotlin-lint`.

## Who it is for: Android developers

The defaults are chosen for Android apps written in Kotlin with Jetpack Compose. Plain
Kotlin/JVM projects work too.

| Android need | What kotlin-lint does by default |
|---|---|
| Agree with Android Studio's formatter | `ktlint_code_style = android_studio`, plus Android Studio's own `ij_kotlin_*` keys in `.editorconfig`, so *Reformat Code* and the linter don't fight |
| Compose naming (`@Composable fun NotesScreen`) | PascalCase allowed for `@Composable` functions (ktlint `function-naming`, detekt `FunctionNaming`) |
| Compose layout values (`16.dp`, `Color(0xFF6650A4)`) | detekt `MagicNumber` ignores `@Composable` / `@Preview` and property declarations |
| Private `@Preview` functions | not reported as unused |
| Composables with many optional parameters | detekt `LongParameterList` / `LongMethod` relaxed for `@Composable` |
| Compose correctness | compose-rules: missing `Modifier` parameter, `MutableState` parameters, composable naming, ViewModel forwarding, and more. Run through ktlint only, so each finding is reported once |
| Kotlin under `src/main/java` | all `*.kt` / `*.kts` files are linted wherever they live, including `build.gradle.kts` |
| Generated code | `build/`, `generated/`, KSP/kapt output are ignored by default |
| Android Lint | not replaced. Android Lint needs the AGP build; kotlin-lint covers Kotlin source quality. The Action docs show uploading both SARIF reports side by side |

These defaults ship as `.editorconfig` and `config/detekt.yml` and are exercised by
`samples/android_app` in the self-test. A project overrides them with its own files.

## Principles (maintainability)

1. **The CLI is the product.** Every other surface (Action, pre-commit, Docker, Gradle) calls
   the same binary with the same flags. Nothing is implemented twice.
2. **One version catalog** (`gradle/libs.versions.toml`) pins ktlint, detekt and Kotlin.
   An engine upgrade is one PR. Golden-file tests show exactly what changed in the output.
3. **Small surface area.** Few flags, stable exit codes, a stable output format.
   Anything else is a reporter option.
4. **Boring distribution.** GitHub Releases with `SHA256SUMS` and build provenance.
   Every installer verifies the checksum.

## User experience

```console
$ kotlin-lint                       # lint the current directory (respects .gitignore)
src/main/kotlin/App.kt:12:5: Unused import 'java.util.List' [ktlint:no-unused-imports]
src/main/kotlin/App.kt:40:1: Function 'run' is too complex (18) [detekt:CyclomaticComplexMethod]
2 problems (1 fixable with --fix)

$ kotlin-lint --fix                 # apply ktlint autocorrections
$ kotlin-lint src/ build.gradle.kts # explicit paths
$ kotlin-lint --changed-since origin/main
$ kotlin-lint --format json|sarif|checkstyle
$ kotlin-lint --init                # write a starter .kotlin-lint.yaml
$ kotlin-lint --version
```

**Exit codes:** `0` clean, `1` problems found, `2` usage or config error, `3` internal error.

**Config:** `.kotlin-lint.yaml`, found by walking up from the current directory (the way
pylint finds `pylintrc`). It is optional.

```yaml
style: android_studio          # or ktlint_official, intellij_idea
fail-on: warning                # error | warning | info
ignore: ["**/build/**", "**/generated/**"]   # these two are the defaults
rules:
  ktlint:no-wildcard-imports: off
  detekt:MagicNumber: { severity: info }
detekt-config: config/detekt.yml   # escape hatch to full detekt config
baseline: .kotlin-lint-baseline.xml
```

`.editorconfig` is still honored, as ktlint users expect. Inline suppression uses
`@Suppress("ktlint:rule-id")` / `@Suppress("RuleName")`, same as the underlying engines.

## Distribution (portability)

| Artifact | For | Notes |
|---|---|---|
| Per-platform archive with a bundled `jlink` runtime (`linux-x64`, `linux-arm64`, `macos-x64`, `macos-arm64`, `windows-x64`) | Everyone, CI | Untar and run, no JDK needed. About 40–60 MB. |
| `kotlin-lint.jar` (fat JAR) | People who already have Java 17+ | `java -jar kotlin-lint.jar` |
| `ghcr.io/opensource-for-freedom/kotlin-lint:<ver>` | Docker users, pre-commit `docker_image` | Multi-arch |
| `scripts/install.sh` / `install.ps1` | Local and CI one-liner | Downloads a pinned version and verifies the sha256 (modelled on actionlint's `download-actionlint.bash`) |
| Homebrew tap, Scoop manifest | Later | Generated by the release workflow |

A **GraalVM native binary** is evaluated later, not promised. ktlint and detekt embed the
Kotlin compiler, which relies heavily on reflection, so native-image builds are fragile.
A bundled `jlink` runtime gets the same "download and run" experience reliably.

## Integrations

**GitHub Action** (`action.yml`, composite, at repo root):
```yaml
- uses: actions/checkout@v4
- uses: opensource-for-freedom/kotlin_lint@v1
  with:
    args: --changed-since ${{ github.event.pull_request.base.sha }}   # optional
```
Steps: run `install.sh` for the version matching the action tag (cached with `actions/cache`),
register `.github/kotlin-lint-matcher.json` (a problem matcher that turns the default output
into PR annotations), then run `kotlin-lint $args`. To upload to code scanning, use
`--format sarif` plus `github/codeql-action/upload-sarif`; the docs include a snippet.

Like actionlint, the docs also show the Action-free way: `run: bash <(curl …/install.sh) && kotlin-lint`.
This works on any CI, not only GitHub.

**pre-commit** (`.pre-commit-hooks.yaml`):
- `kotlin-lint`: `language: script` through the install script. Runs on staged `.kt`/`.kts` files.
- `kotlin-lint-fix`: same, with `--fix`.
- `kotlin-lint-docker`: `language: docker_image`, for people who'd rather not download binaries.

**Gradle plugin** (Phase 4, kept thin). Android developers live in Gradle and Android Studio, so
this matters more for them than for most Kotlin users. It adds a `kotlinLint` task that calls the same
`core` in-process. Its one extra feature is detekt **type resolution**, which needs the compile
classpath that only Gradle has. Everything else is identical to the CLI.

## Repository layout

```
kotlin_lint/
├── gradle/libs.versions.toml   # the only place engine versions live
├── core/                       # finding model, ktlint + detekt runners, config, reporters, baseline
├── cli/                        # clikt entry point → fat JAR → jlink images
├── rules/                      # custom ktlint + detekt rules (later)
├── config/                     # default detekt.yml / editorconfig shipped inside the JAR
├── scripts/install.sh, install.ps1
├── action.yml
├── .pre-commit-hooks.yaml
├── .github/kotlin-lint-matcher.json
├── Dockerfile
├── samples/{kotlin_actions,violations}/  # fixtures for e2e and golden tests
└── .github/workflows/{ci,release}.yml
```

## Core design

- **Finding model:** `Finding(tool, rule, severity, path, line, col, message, fixable)`.
  Both engines map into it, and every reporter consumes only this.
- **Engines run in-process**, each in its own classloader, because ktlint and detekt embed
  different `kotlin-compiler-embeddable` versions. **This is the main technical risk.**
  A spike in Phase 1 proves the approach first. If it fails, the fallback is to run each
  engine as a sub-process from the same distribution.
- **File discovery:** respects `.gitignore` and `ignore:`. `--changed-since` uses `git diff --name-only`.
- **Baseline:** one file covering both engines. `kotlin-lint --write-baseline` creates it, so
  existing codebases can adopt the tool incrementally.

## CI / release for this repo

- **ci.yml** (push and PR): `./gradlew build` (unit + golden tests + self-lint) on ubuntu,
  macOS and Windows. Also an e2e job that builds the jlink image, runs it against
  `samples/kotlin_actions` (expects exit 0) and `samples/violations` (expects exit 1 with the golden
  output), and runs the Action from `./` against both samples.
- **release.yml** (on a `v*` tag): build the fat JAR, the jlink archives for each platform
  (a matrix over each OS runner), and the multi-arch Docker image. Then `SHA256SUMS`,
  `actions/attest-build-provenance`, the GitHub Release, and moving the `v1` tag.
- **Versioning:** semver. Bumping ktlint or detekt, or turning a new rule on by default, is a
  minor release with release notes that call it out. Changes to flags, exit codes, output
  format or Action inputs are major releases.
- **Dependabot**, grouped so ktlint, detekt and Kotlin move together.

## Phases

| Phase | Deliverable | Done when |
|---|---|---|
| 0. Scaffold | Gradle multi-module, version catalog, wrapper, LICENSE, ci.yml | `./gradlew build` green on 3 OSes |
| 1. ktlint MVP | Core, ktlint runner, CLI (`lint`, `--fix`, paths, exit codes, default output), classloader spike | Golden tests on `samples/` pass |
| 2. detekt | detekt runner, `.kotlin-lint.yaml`, json/sarif/checkstyle, baseline, `--changed-since` | One run, both engines, one report |
| 3. Portable v1 | jlink archives, fat JAR, install scripts, Action + problem matcher, release.yml | Fresh repo on each OS: one install step, same output locally and in CI |
| 4. Android Gradle integration | Thin Gradle plugin (`kotlinLint` task wired into `check`, works with AGP multi-module builds and per-variant source sets, detekt type resolution) | `samples/android_app` built with AGP lints through Gradle with the same findings as the CLI |
| 5. Ecosystem | pre-commit hooks, Docker image, Homebrew/Scoop | Hooks work in a scratch repo |
| 6. Extras | Custom rules, native-binary evaluation | — |

Phases 0–3 make the first release.

## Open questions

1. Defaults: the self-test uses `android_studio` style plus the Compose overrides above. Which other
   detekt rules should be off for Android (for example `TooManyFunctions` in ViewModels)?
2. Minimum JDK for the fat JAR: 17?
3. License: Apache-2.0 matches ktlint and detekt.
4. Should the docs examples pin the Action by full commit SHA? This repo's own CI already does.
5. Kotlin Multiplatform (`commonMain`, `androidMain`, `iosMain`) in scope for v1?
