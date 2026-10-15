#!/usr/bin/env bash
# Self-test: lint the sample projects and write a Markdown report.
#
#   samples/kotlin_actions  must lint clean   (no false positives)
#   samples/violations      must be flagged   (the linter really ran)
#
# Runs the same way locally and in CI:
#   ./scripts/selftest.sh                 # report -> selftest-report.md
#   REPORT=out.md ./scripts/selftest.sh
# In GitHub Actions the report is also appended to $GITHUB_STEP_SUMMARY.
#
# Until the kotlin-lint CLI exists (build plan, Phase 1) this drives the pinned
# ktlint and detekt engines directly. Requires: bash, curl, Java 17+.
set -euo pipefail

KTLINT_VERSION=1.8.0
KTLINT_SHA256=369ad2b789f95a011f807e1fcb690ccef80bd7cd014fd139e73ae82dcc0baeab
DETEKT_VERSION=1.23.8
DETEKT_SHA256=3afe89a11120303c73c9bdda3d8fe558dd9070a6937d27819ddc04b275381245
MAVEN=https://repo1.maven.org/maven2

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CACHE=${KOTLIN_LINT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kotlin-lint/tools}
REPORT=${REPORT:-$ROOT/selftest-report.md}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch <url> <sha256> -> prints cached path; refuses a jar whose hash does not match.
fetch() {
  local url=$1 want=$2 dest
  dest="$CACHE/$(basename "$url")"
  if [[ ! -f $dest || $(sha256 "$dest") != "$want" ]]; then
    mkdir -p "$CACHE"
    curl -fsSL --retry 3 -o "$dest.part" "$url"
    if [[ $(sha256 "$dest.part") != "$want" ]]; then
      rm -f "$dest.part"
      echo "checksum mismatch for $url" >&2
      exit 3
    fi
    mv "$dest.part" "$dest"
  fi
  echo "$dest"
}

KTLINT=$(fetch "$MAVEN/com/pinterest/ktlint/ktlint-cli/$KTLINT_VERSION/ktlint-cli-$KTLINT_VERSION-all.jar" "$KTLINT_SHA256")
DETEKT=$(fetch "$MAVEN/io/gitlab/arturbosch/detekt/detekt-cli/$DETEKT_VERSION/detekt-cli-$DETEKT_VERSION-all.jar" "$DETEKT_SHA256")

# Each run_* writes findings (one per line) to $WORK/<name>.txt and echoes the count.
run_ktlint() {
  local name=$1 dir=$2 out="$WORK/$1.txt"
  (cd "$ROOT" && java -jar "$KTLINT" --relative "$dir/**/*.kt" 2>/dev/null) \
    | grep -E ':[0-9]+:[0-9]+: ' >"$out" || true
  wc -l <"$out" | tr -d ' '
}

# Paths handed to Java must be native. Git Bash on Windows converts plain path
# arguments, but not one embedded in a value like "txt:/tmp/x", so convert explicitly.
native() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi
}

run_detekt() {
  local name=$1 dir=$2 out="$WORK/$1.txt" raw="$WORK/$1.raw" root
  root=$(native "$ROOT")
  (cd "$ROOT" && java -jar "$DETEKT" --input "$dir" --base-path "$root" \
    --report "txt:$(native "$raw")" >"$WORK/$name.log" 2>&1) || true
  # No report means detekt did not run; never read that as "0 findings".
  if [[ ! -f $raw ]]; then
    echo "detekt produced no report for $dir:" >&2
    cat "$WORK/$name.log" >&2
    exit 3
  fi
  sed -E -e 's/ - Signature=.*$//' -e 's|\\|/|g' -e "s|$root/||" -e "s|$ROOT/||" "$raw" \
    | grep -v '^$' >"$out" || true
  wc -l <"$out" | tr -d ' '
}

pass=true
rows=()
# check <engine> <version> <sample> <expect: clean|flagged>
check() {
  local engine=$1 version=$2 sample=$3 expect=$4 name count ok
  name="$engine-$(basename "$sample")"
  count=$("run_$engine" "$name" "$sample")
  if [[ $expect == clean ]]; then [[ $count -eq 0 ]] && ok=true || ok=false
  else [[ $count -gt 0 ]] && ok=true || ok=false; fi
  $ok || pass=false
  rows+=("| $engine $version | \`$sample\` | $expect | $count finding(s) | $($ok && echo '✅ pass' || echo '❌ fail') |")
  echo "$engine on $sample: $count finding(s), expected $expect -> $($ok && echo pass || echo FAIL)" >&2
}

check ktlint "$KTLINT_VERSION" samples/kotlin_actions clean
check detekt "$DETEKT_VERSION" samples/kotlin_actions clean
check ktlint "$KTLINT_VERSION" samples/violations flagged
check detekt "$DETEKT_VERSION" samples/violations flagged

details() {
  local title=$1 file=$2
  [[ -s $file ]] || return 0
  printf '\n<details><summary>%s</summary>\n\n```text\n' "$title"
  cat "$file"
  printf '```\n\n</details>\n'
}

{
  if $pass; then echo "# ✅ kotlin-lint self-test passed"; else echo "# ❌ kotlin-lint self-test failed"; fi
  echo
  echo "| Engine | Sample | Expected | Result | Status |"
  echo "|---|---|---|---|---|"
  printf '%s\n' "${rows[@]}"
  echo
  echo "\`kotlin_actions\` must be clean; \`violations\` must be flagged, which proves the engines actually ran."
  details "Unexpected findings in kotlin_actions (ktlint)" "$WORK/ktlint-kotlin_actions.txt"
  details "Unexpected findings in kotlin_actions (detekt)" "$WORK/detekt-kotlin_actions.txt"
  details "Expected findings in violations (ktlint)" "$WORK/ktlint-violations.txt"
  details "Expected findings in violations (detekt)" "$WORK/detekt-violations.txt"
  echo
  echo "<sub>$(uname -s) · $(java -version 2>&1 | grep -m1 -E 'version') · ktlint sha256 \`${KTLINT_SHA256:0:12}…\` · detekt sha256 \`${DETEKT_SHA256:0:12}…\`</sub>"
} >"$REPORT"

[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$REPORT" >>"$GITHUB_STEP_SUMMARY"
echo "report: $REPORT" >&2
$pass
