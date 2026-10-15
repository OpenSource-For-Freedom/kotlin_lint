#!/usr/bin/env bash
# Self-test: lint the sample projects with the Android defaults and write a Markdown report.
#
#   samples/android_app     Jetpack Compose app        must lint clean   (no false positives)
#   samples/kotlin_actions  plain Kotlin app           must lint clean
#   samples/violations      deliberately bad code      must be flagged by every engine
#                                                      (proves each engine really ran)
#
# Runs the same way locally and in CI, on Linux, macOS and Windows (Git Bash):
#   ./scripts/selftest.sh                 # report -> selftest-report.md
#   REPORT=out.md ./scripts/selftest.sh
# In GitHub Actions the report is also appended to $GITHUB_STEP_SUMMARY.
#
# Until the kotlin-lint CLI exists (build plan, Phase 1) this drives the pinned
# engines directly. Requires: bash, curl, a JDK 17+ (java and jar).
set -euo pipefail

KTLINT_VERSION=1.8.0
KTLINT_SHA256=369ad2b789f95a011f807e1fcb690ccef80bd7cd014fd139e73ae82dcc0baeab
DETEKT_VERSION=1.23.8
DETEKT_SHA256=3afe89a11120303c73c9bdda3d8fe558dd9070a6937d27819ddc04b275381245
# Jetpack Compose rules (mrmans0n/compose-rules), run through ktlint only so each
# Compose finding is reported once. Maven Central has no fat jar, so the ruleset
# and its one dependency are merged locally after both checksums pass.
COMPOSE_VERSION=0.6.8
COMPOSE_SHA256=be00995f535e866a075200bf8c385962438603c3a17254bb255b3c2c07a951ef
COMPOSE_COMMON_SHA256=ecd04db72cc8ce20cc9c99a84450443906f81f20553e1aa4c9b7b2b6638ed549
MAVEN=https://repo1.maven.org/maven2

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CACHE=${KOTLIN_LINT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kotlin-lint/tools}
REPORT=${REPORT:-$ROOT/selftest-report.md}
DETEKT_CONFIG=$ROOT/config/detekt.yml
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Paths handed to Java must be native. Git Bash on Windows converts plain path
# arguments, but not one embedded in a value like "txt:/tmp/x", so convert explicitly.
native() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi
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

JAR=jar
[[ -n ${JAVA_HOME:-} && -x $JAVA_HOME/bin/jar ]] && JAR=$JAVA_HOME/bin/jar
command -v "$JAR" >/dev/null || { echo "a JDK is required ('jar' not found)" >&2; exit 2; }

KTLINT=$(fetch "$MAVEN/com/pinterest/ktlint/ktlint-cli/$KTLINT_VERSION/ktlint-cli-$KTLINT_VERSION-all.jar" "$KTLINT_SHA256")
DETEKT=$(fetch "$MAVEN/io/gitlab/arturbosch/detekt/detekt-cli/$DETEKT_VERSION/detekt-cli-$DETEKT_VERSION-all.jar" "$DETEKT_SHA256")
COMPOSE_JAR=$(fetch "$MAVEN/io/nlopez/compose/rules/ktlint/$COMPOSE_VERSION/ktlint-$COMPOSE_VERSION.jar" "$COMPOSE_SHA256")
COMPOSE_COMMON_JAR=$(fetch "$MAVEN/io/nlopez/compose/rules/common-ktlint/$COMPOSE_VERSION/common-ktlint-$COMPOSE_VERSION.jar" "$COMPOSE_COMMON_SHA256")

COMPOSE_RULES=$CACHE/compose-rules-ktlint-$COMPOSE_VERSION-merged.jar
if [[ ! -f $COMPOSE_RULES ]]; then
  mkdir -p "$WORK/compose"
  (cd "$WORK/compose" && "$JAR" xf "$(native "$COMPOSE_COMMON_JAR")" && "$JAR" xf "$(native "$COMPOSE_JAR")")
  "$JAR" cf "$(native "$COMPOSE_RULES.part")" -C "$(native "$WORK/compose")" .
  mv "$COMPOSE_RULES.part" "$COMPOSE_RULES"
fi

# ktlint prints "path:line:col: message (rule)"; Compose rules continue the message
# over several lines. Collapse each finding to one line: "path:line:col: first line (rule)".
collapse_ktlint() {
  awk '
    function flush() { if (loc != "") { print loc " (" rule ")"; loc = "" } }
    /^[^ ].*:[0-9]+:[0-9]+: / {
      flush()
      loc = $0; rule = "?"
      if (match(loc, / \([a-z-]+:[a-z0-9-]+\)$/)) { rule = substr(loc, RSTART + 2, RLENGTH - 3); loc = substr(loc, 1, RSTART - 1) }
      next
    }
    loc != "" && match($0, /\([a-z-]+:[a-z0-9-]+\)$/) { rule = substr($0, RSTART + 1, RLENGTH - 2) }
    END { flush() }
  '
}

# lint_ktlint <sample>: writes ktlint-<s>.txt (ktlint rules) and compose-<s>.txt (compose rules).
lint_ktlint() {
  local s=$1 name all
  name=$(basename "$s"); all="$WORK/ktlint-all-$name.txt"
  (cd "$ROOT" && java -jar "$KTLINT" --relative --ruleset="$(native "$COMPOSE_RULES")" \
    "$s/**/*.kt" "$s/**/*.kts" 2>"$WORK/ktlint-$name.log") | collapse_ktlint >"$all" || true
  grep -v '(compose:' "$all" >"$WORK/ktlint-$name.txt" || true
  grep '(compose:' "$all" >"$WORK/compose-$name.txt" || true
}

# lint_detekt <sample>: writes detekt-<s>.txt.
lint_detekt() {
  local s=$1 name raw root
  name=$(basename "$s"); raw="$WORK/detekt-$name.raw"; root=$(native "$ROOT")
  (cd "$ROOT" && java -jar "$DETEKT" --input "$s" --base-path "$root" \
    --config "$(native "$DETEKT_CONFIG")" --build-upon-default-config \
    --report "txt:$(native "$raw")" >"$WORK/detekt-$name.log" 2>&1) || true
  # No report means detekt did not run; never read that as "0 findings".
  if [[ ! -f $raw ]]; then
    echo "detekt produced no report for $s:" >&2
    cat "$WORK/detekt-$name.log" >&2
    exit 3
  fi
  sed -E -e 's/ - Signature=.*$//' -e 's|\\|/|g' -e "s|$root/||" -e "s|$ROOT/||" "$raw" \
    | grep -v '^$' >"$WORK/detekt-$name.txt" || true
}

pass=true
rows=()
# check <engine> <label> <sample> <expect: clean|flagged>
check() {
  local engine=$1 label=$2 sample=$3 expect=$4 count ok
  count=$(wc -l <"$WORK/$engine-$(basename "$sample").txt" | tr -d ' ')
  if [[ $expect == clean ]]; then [[ $count -eq 0 ]] && ok=true || ok=false
  else [[ $count -gt 0 ]] && ok=true || ok=false; fi
  $ok || pass=false
  rows+=("| $label | \`$sample\` | $expect | $count finding(s) | $($ok && echo '✅ pass' || echo '❌ fail') |")
  echo "$label on $sample: $count finding(s), expected $expect -> $($ok && echo pass || echo FAIL)" >&2
}

SAMPLES=(samples/android_app samples/kotlin_actions samples/violations)
for s in "${SAMPLES[@]}"; do
  lint_ktlint "$s"
  lint_detekt "$s"
  expect=clean
  [[ $s == samples/violations ]] && expect=flagged
  check ktlint "ktlint $KTLINT_VERSION" "$s" $expect
  check compose "compose-rules $COMPOSE_VERSION" "$s" $expect
  check detekt "detekt $DETEKT_VERSION" "$s" $expect
done

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
  echo "Android defaults: \`android_studio\` code style, Jetpack Compose rules, Compose-aware detekt config."
  echo
  echo "| Engine | Sample | Expected | Result | Status |"
  echo "|---|---|---|---|---|"
  printf '%s\n' "${rows[@]}"
  echo
  echo "Clean samples must have zero findings; \`violations\` must be flagged by every engine, which proves each one actually ran."
  for s in "${SAMPLES[@]}"; do
    name=$(basename "$s")
    kind="Unexpected"; [[ $s == samples/violations ]] && kind="Expected"
    details "$kind findings in $name (ktlint)" "$WORK/ktlint-$name.txt"
    details "$kind findings in $name (compose-rules)" "$WORK/compose-$name.txt"
    details "$kind findings in $name (detekt)" "$WORK/detekt-$name.txt"
  done
  echo
  echo "<sub>$(uname -s) · $(java -version 2>&1 | grep -m1 -E 'version')</sub>"
} >"$REPORT"

[[ -n ${GITHUB_STEP_SUMMARY:-} ]] && cat "$REPORT" >>"$GITHUB_STEP_SUMMARY"
echo "report: $REPORT" >&2
$pass
