# Samples

Fixture projects used by the self-test (`scripts/selftest.sh`).

| Sample | Expectation |
|---|---|
| `kotlin_actions/` | A small, clean Kotlin app (a toy GitHub-Actions-style step runner). Must lint with **zero** findings. |
| `violations/` | Deliberately bad code. Must produce findings from **every** engine. This is the positive control: a passing self-test proves the linter really ran, not just that it found nothing. |

`violations/` must stay excluded from any repo-wide lint of this project's own sources.
