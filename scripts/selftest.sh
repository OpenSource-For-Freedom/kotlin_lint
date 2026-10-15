#!/usr/bin/env bash
# Self-test: proves every scan feature works with the Android defaults, and writes a Markdown report.
#
#   1. Samples      samples/android_app and samples/kotlin_actions lint clean;
#                   samples/violations is flagged by every engine.
#   2. Features     each tests/cases/<case>/ must produce exactly the findings in its
#                   expected.txt ("engine rule file:line"); nothing missing, nothing extra.
#   3. Fix          ktlint --format output equals tests/format/Messy.formatted.kt and only
#                   unfixable findings remain.
#   4. Tooling      a wrong checksum is refused; a missing engine report is an error, never "clean".
#
# Runs the same way locally and in CI, on Linux, macOS and Windows (Git Bash):
#   ./scripts/selftest.sh                    # report -> selftest-report.md
#   REPORT=out.md ./scripts/selftest.sh
#   UPDATE_EXPECTED=1 ./scripts/selftest.sh  # rewrite expected.txt files; review the diff!
# In GitHub Actions the report is also appended to $GITHUB_STEP_SUMMARY.
# Exit codes: 0 all passed, 1 a test failed, 2 missing prerequisite, 3 engine/tooling error.
set -euo pipefail

source "$(dirname "$0")/lib.sh"

REPORT=${REPORT:-$ROOT/selftest-report.md}
WORK=$(mktemp -d)
SCRATCH=$ROOT/selftest-work   # visible dir under ROOT: ktlint skips hidden directories
trap 'rm -rf "$WORK" "$SCRATCH"' EXIT

setup_tools

pass=true
total=0
failed=0
SAMPLE_ROWS=()
FEATURE_ROWS=()
OTHER_ROWS=()
DETAILS=()

# result <ok:true|false>: sets CELL and updates the counters. Never call it inside $(...):
# a subshell would drop the counter updates and hide failures.
result() {
  total=$((total + 1))
  if $1; then CELL="✅ pass"; else pass=false; failed=$((failed + 1)); CELL="❌ fail"; fi
}

block() { # block <title> <file>: collapsible details section
  [[ -s $2 ]] || return 0
  DETAILS+=("$(printf '<details><summary>%s</summary>\n\n```text\n%s\n```\n\n</details>\n' "$1" "$(cat "$2")")")
}

# ---------------------------------------------------------------- 1. samples
for s in samples/android_app samples/kotlin_actions samples/violations; do
  name=$(basename "$s")
  lint_ktlint "$WORK/k-$name" "$s"
  lint_detekt "$WORK/d-$name" "$s"
  grep -v '(compose:' "$WORK/k-$name" >"$WORK/ktlint-$name" || true
  grep '(compose:' "$WORK/k-$name" >"$WORK/compose-$name" || true
  cp "$WORK/d-$name" "$WORK/detekt-$name"
  expect=clean; [[ $name == violations ]] && expect=flagged
  for engine in ktlint compose detekt; do
    count=$(wc -l <"$WORK/$engine-$name" | tr -d ' ')
    if [[ $expect == clean ]]; then ok=$([[ $count -eq 0 ]] && echo true || echo false)
    else ok=$([[ $count -gt 0 ]] && echo true || echo false); fi
    result "$ok"
    SAMPLE_ROWS+=("| \`$s\` | $engine | $expect | $count | $CELL |")
    [[ $expect == clean && $count -gt 0 ]] && block "Unexpected $engine findings in $name" "$WORK/$engine-$name"
  done
  echo "samples: $s done" >&2
done

# ---------------------------------------------------------------- 2. feature cases
# One ktlint run and one detekt run over all cases, then split per case directory.
lint_ktlint "$WORK/cases.k" tests/cases
lint_detekt "$WORK/cases.d" tests/cases
cat "$WORK/cases.k" "$WORK/cases.d" | normalize >"$WORK/cases.all"

for dir in "$ROOT"/tests/cases/*/; do
  case=$(basename "$dir")
  expected_file=$dir/expected.txt
  prefix="tests/cases/$case/"
  grep -F " $prefix" "$WORK/cases.all" | sed "s| $prefix| |" >"$WORK/actual-$case" || true
  if [[ -n ${UPDATE_EXPECTED:-} ]]; then
    { grep '^#' "$expected_file" 2>/dev/null || true; cat "$WORK/actual-$case"; } >"$expected_file.new"
    mv "$expected_file.new" "$expected_file"
  fi
  { tr -d '\r' <"$expected_file" | grep -v -e '^#' -e '^$' || true; } | LC_ALL=C sort -u >"$WORK/expected-$case"
  LC_ALL=C comm -23 "$WORK/expected-$case" "$WORK/actual-$case" | sed 's/^/missing:    /' >"$WORK/diff-$case"
  LC_ALL=C comm -13 "$WORK/expected-$case" "$WORK/actual-$case" | sed 's/^/unexpected: /' >>"$WORK/diff-$case"
  ok=$([[ ! -s $WORK/diff-$case ]] && echo true || echo false)
  what=$(grep -m1 '^#' "$expected_file" | sed 's/^# *//')
  n=$(wc -l <"$WORK/expected-$case" | tr -d ' ')
  result "$ok"
  FEATURE_ROWS+=("| \`$case\` | $what | $n | $CELL |")
  block "\`$case\`: difference from expected.txt" "$WORK/diff-$case"
done
echo "features: $(ls -d "$ROOT"/tests/cases/*/ | wc -l | tr -d ' ') cases done" >&2

# ---------------------------------------------------------------- 3. --fix (ktlint --format)
mkdir -p "$SCRATCH/format"
cp "$ROOT/tests/format/Messy.kt" "$SCRATCH/format/"
lint_ktlint "$WORK/fmt-before" selftest-work/format
before=$(wc -l <"$WORK/fmt-before" | tr -d ' ')
format_ktlint selftest-work/format
lint_ktlint "$WORK/fmt-after" selftest-work/format
normalize <"$WORK/fmt-after" | sed 's| selftest-work/format/| |' >"$WORK/fmt-actual"
{ tr -d '\r' <"$ROOT/tests/format/expected.txt" | grep -v -e '^#' -e '^$' || true; } | LC_ALL=C sort -u >"$WORK/fmt-expected"
same_output=$(cmp -s "$SCRATCH/format/Messy.kt" "$ROOT/tests/format/Messy.formatted.kt" && echo true || echo false)
same_left=$(cmp -s "$WORK/fmt-actual" "$WORK/fmt-expected" && echo true || echo false)
result "$same_output"
OTHER_ROWS+=("| \`--fix\` output matches \`tests/format/Messy.formatted.kt\` | $CELL |")
result "$same_left"
OTHER_ROWS+=("| \`--fix\` leaves only unfixable findings ($before before → $(wc -l <"$WORK/fmt-actual" | tr -d ' ') after) | $CELL |")
if ! $same_output; then
  diff "$ROOT/tests/format/Messy.formatted.kt" "$SCRATCH/format/Messy.kt" >"$WORK/fmt-diff" || true
  block "\`--fix\` output differs from Messy.formatted.kt" "$WORK/fmt-diff"
fi
$same_left || block "\`--fix\` remaining findings" "$WORK/fmt-actual"
echo "fix: done" >&2

# ---------------------------------------------------------------- 4. tooling
# A download whose sha256 does not match is refused (exit 3) and never cached.
set +e
(CACHE="$WORK/badcache"; fetch "$MAVEN/com/pinterest/ktlint/ktlint-cli/$KTLINT_VERSION/ktlint-cli-$KTLINT_VERSION.pom" \
  0000000000000000000000000000000000000000000000000000000000000000 >/dev/null 2>&1)
rc=$?
set -e
ok=$([[ $rc -eq 3 && -z $(ls -A "$WORK/badcache" 2>/dev/null) ]] && echo true || echo false)
result "$ok"
OTHER_ROWS+=("| Wrong checksum is refused and nothing is cached (exit $rc) | $CELL |")

# If detekt produces no report, that is an error (exit 3), never "0 findings".
set +e
(lint_detekt "$WORK/missing" does/not/exist >/dev/null 2>&1)
rc=$?
set -e
result "$([[ $rc -eq 3 ]] && echo true || echo false)"
OTHER_ROWS+=("| Missing detekt report is an error, not a clean result (exit $rc) | $CELL |")
echo "tooling: done" >&2

# ---------------------------------------------------------------- report
{
  if $pass; then echo "# ✅ kotlin-lint self-test passed ($total/$total)"
  else echo "# ❌ kotlin-lint self-test failed ($failed of $total failed)"; fi
  echo
  echo "Android defaults: \`android_studio\` style · Jetpack Compose rules $COMPOSE_VERSION · Compose-aware detekt config."
  echo "Engines: ktlint $KTLINT_VERSION · detekt $DETEKT_VERSION, all pinned and sha256-verified."
  echo
  echo "## Samples"
  echo
  echo "| Sample | Engine | Expected | Findings | Status |"
  echo "|---|---|---|---|---|"
  printf '%s\n' "${SAMPLE_ROWS[@]}"
  echo
  echo "## Scan features"
  echo
  echo "Each case must produce exactly the findings in its \`expected.txt\` (rule and line), nothing missing and nothing extra."
  echo
  echo "| Case | What it checks | Expected findings | Status |"
  echo "|---|---|---|---|"
  printf '%s\n' "${FEATURE_ROWS[@]}"
  echo
  echo "## Fix and tooling"
  echo
  echo "| Check | Status |"
  echo "|---|---|"
  printf '%s\n' "${OTHER_ROWS[@]}"
  if [[ ${#DETAILS[@]} -gt 0 ]]; then
    echo
    echo "## Failures"
    echo
    printf '%s\n' "${DETAILS[@]}"
  fi
  echo
  echo "<sub>$(uname -s) · $(java -version 2>&1 | grep -m1 -E 'version')</sub>"
} >"$REPORT"

[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$REPORT" >>"$GITHUB_STEP_SUMMARY"
# Failures also go to the log, so CI output says what broke without opening the report.
if ! $pass; then
  echo "FAILED:" >&2
  printf '%s\n' "${SAMPLE_ROWS[@]}" "${FEATURE_ROWS[@]}" "${OTHER_ROWS[@]}" | grep '❌' >&2 || true
  [[ ${#DETAILS[@]} -gt 0 ]] && printf '%s\n' "${DETAILS[@]}" | grep -v -e '^<details' -e '^</details' -e '^```' -e '^$' >&2
fi
echo "report: $REPORT ($((total - failed))/$total passed)" >&2
$pass
