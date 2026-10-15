# Shared engine setup for scripts/selftest.sh. Source it; do not run it.
#
# Pins every engine by version and sha256, downloads into a cache, and exposes:
#   setup_tools                         download/verify engines, build the Compose ruleset jar
#   lint_ktlint <out> <paths...>        ktlint + Compose rules, one finding per line
#   lint_detekt <out> <input>           detekt with config/detekt.yml, one finding per line
#   normalize                           "engine rule file:line" lines, sorted (for exact comparison)
# Works on Linux, macOS and Windows (Git Bash). Requires: bash, curl, a JDK 17+ (java and jar).

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

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CACHE=${KOTLIN_LINT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kotlin-lint/tools}
DETEKT_CONFIG=$ROOT/config/detekt.yml

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Paths handed to Java must be native. Git Bash on Windows converts plain path
# arguments, but not one embedded in a value like "txt:/tmp/x", so convert explicitly.
native() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi
}

# fetch <url> <sha256> -> prints cached path; refuses a file whose hash does not match.
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

setup_tools() {
  local jar=jar tmp
  [[ -n ${JAVA_HOME:-} && -x $JAVA_HOME/bin/jar ]] && jar=$JAVA_HOME/bin/jar
  command -v "$jar" >/dev/null || { echo "a JDK is required ('jar' not found)" >&2; exit 2; }

  KTLINT=$(fetch "$MAVEN/com/pinterest/ktlint/ktlint-cli/$KTLINT_VERSION/ktlint-cli-$KTLINT_VERSION-all.jar" "$KTLINT_SHA256")
  DETEKT=$(fetch "$MAVEN/io/gitlab/arturbosch/detekt/detekt-cli/$DETEKT_VERSION/detekt-cli-$DETEKT_VERSION-all.jar" "$DETEKT_SHA256")
  local compose common
  compose=$(fetch "$MAVEN/io/nlopez/compose/rules/ktlint/$COMPOSE_VERSION/ktlint-$COMPOSE_VERSION.jar" "$COMPOSE_SHA256")
  common=$(fetch "$MAVEN/io/nlopez/compose/rules/common-ktlint/$COMPOSE_VERSION/common-ktlint-$COMPOSE_VERSION.jar" "$COMPOSE_COMMON_SHA256")

  COMPOSE_RULES=$CACHE/compose-rules-ktlint-$COMPOSE_VERSION-merged.jar
  if [[ ! -f $COMPOSE_RULES ]]; then
    tmp=$(mktemp -d)
    (cd "$tmp" && "$jar" xf "$(native "$common")" && "$jar" xf "$(native "$compose")")
    "$jar" cf "$(native "$COMPOSE_RULES.part")" -C "$(native "$tmp")" .
    mv "$COMPOSE_RULES.part" "$COMPOSE_RULES"
    rm -rf "$tmp"
  fi
}

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

# lint_ktlint <out> <dir>: every *.kt and *.kts under <dir> (relative to ROOT).
lint_ktlint() {
  local out=$1 dir=$2
  (cd "$ROOT" && java -jar "$KTLINT" --relative --ruleset="$(native "$COMPOSE_RULES")" \
    "$dir/**/*.kt" "$dir/**/*.kts" 2>"$out.log") | collapse_ktlint >"$out" || true
}

# ktlint --format in place on every *.kt and *.kts under <dir>.
format_ktlint() {
  local dir=$1
  (cd "$ROOT" && java -jar "$KTLINT" --format --relative --ruleset="$(native "$COMPOSE_RULES")" \
    "$dir/**/*.kt" "$dir/**/*.kts" >/dev/null 2>&1) || true
}

# lint_detekt <out> <input>: <input> is relative to ROOT.
lint_detekt() {
  local out=$1 input=$2 raw="$1.raw" root
  root=$(native "$ROOT")
  rm -f "$raw"
  (cd "$ROOT" && java -jar "$DETEKT" --input "$input" --base-path "$root" \
    --config "$(native "$DETEKT_CONFIG")" --build-upon-default-config \
    --report "txt:$(native "$raw")" >"$out.log" 2>&1) || true
  # No report means detekt did not run; never read that as "0 findings".
  if [[ ! -f $raw ]]; then
    echo "detekt produced no report for $input:" >&2
    cat "$out.log" >&2
    exit 3
  fi
  sed -E -e 's/ - Signature=.*$//' -e 's|\\|/|g' -e "s|$root/||" -e "s|$ROOT/||" "$raw" \
    | grep -v '^$' >"$out" || true
}

# Reads ktlint and/or detekt finding lines on stdin; prints "engine rule file:line", sorted, unique.
#   ktlint:  path:12:5: message (standard:indent)        -> ktlint standard:indent path:12
#            path:9:1: message (compose:naming-check)    -> compose compose:naming-check path:9
#   detekt:  MagicNumber - [fn] at path:4:30             -> detekt MagicNumber path:4
normalize() {
  sed -E \
    -e 's/^(.*):([0-9]+):[0-9]+: .* \((compose:[a-z0-9-]+)\)$/compose \3 \1:\2/' \
    -e 's/^(.*):([0-9]+):[0-9]+: .* \(([a-z-]+:[a-z0-9-]+)\)$/ktlint \3 \1:\2/' \
    -e 's/^([A-Za-z]+) - .* at (.*):([0-9]+):[0-9]+$/detekt \1 \2:\3/' \
    | LC_ALL=C sort -u
}
