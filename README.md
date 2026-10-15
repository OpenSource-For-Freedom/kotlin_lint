# kotlin_lint

Linting for Kotlin **Android** projects: ktlint (Android Studio style), detekt and the Jetpack Compose rules,
with defaults that understand Compose. It runs the same way locally and in CI.

The Android defaults live in [`.editorconfig`](.editorconfig) and [`config/detekt.yml`](config/detekt.yml).
See [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) for the roadmap.

## Self-test

`samples/android_app` (Jetpack Compose) and `samples/kotlin_actions` must lint clean, and `samples/violations` is
deliberately bad code. The self-test lints all three and writes a Markdown report:

```console
./scripts/selftest.sh        # needs bash, curl and a JDK 17+; writes selftest-report.md
```

It passes only when the clean samples have zero findings **and** `violations` is flagged by every engine.
CI runs the same script on Linux, macOS and Windows (`.github/workflows/selftest.yml`) and shows
the report as the job summary.
