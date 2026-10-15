# kotlin_lint
Kotlin lint tool

## Self-test

`samples/kotlin_actions` is a small clean Kotlin app and `samples/violations` is deliberately bad code.
The self-test lints both and writes a Markdown report:

```console
./scripts/selftest.sh        # needs bash, curl and Java 17+; writes selftest-report.md
```

It passes only when `kotlin_actions` is clean **and** `violations` is flagged by every engine.
CI runs the same script on Linux, macOS and Windows (`.github/workflows/selftest.yml`) and shows
the report as the job summary.

See [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) for the roadmap.
