# Shared engine setup for scripts/selftest.sh. Source it; do not run it.
#
# Pins every engine by version and sha256, downloads into a cache, and exposes:
#   setup_tools                         download/verify engines, build the Compose ruleset jar
#   lint_ktlint <out> <dir>             ktlint + Compose rules, one finding per line
#   format_ktlint <dir>                 ktlint --format in place
#   lint_detekt <out> <dir>             detekt with config/detekt.yml, one finding per line
#                                       (also <out>.xml, with messages, for the CLI)
#   <dir> is relative to $BASE (default: this repo). The CLI sets BASE to the current directory.
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
DEFAULT_EDITORCONFIG=$ROOT/.editorconfig
# Never lint build output or generated sources.
EXCLUDES='**/build/**,**/generated/**'

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

# ktlint arguments shared by lint and format. --editorconfig supplies the Android defaults
# only for properties the project's own .editorconfig files do not set.
ktlint_args() {
  local dir=$1
  printf '%s\n' --relative --ruleset="$(native "$COMPOSE_RULES")" \
    --editorconfig="$(native "$DEFAULT_EDITORCONFIG")" \
    "$dir/**/*.kt" "$dir/**/*.kts" "!**/build/**" "!**/generated/**"
}

# lint_ktlint <out> <dir>: every *.kt and *.kts under <dir>.
lint_ktlint() {
  local out=$1 dir=$2 args=()
  while IFS= read -r a; do args+=("$a"); done < <(ktlint_args "$dir")
  (cd "${BASE:-$ROOT}" && java -jar "$KTLINT" "${args[@]}" 2>"$out.log") | collapse_ktlint >"$out" || true
}

# format_ktlint <dir>: ktlint --format in place on every *.kt and *.kts under <dir>.
format_ktlint() {
  local dir=$1 args=()
  while IFS= read -r a; do args+=("$a"); done < <(ktlint_args "$dir")
  (cd "${BASE:-$ROOT}" && java -jar "$KTLINT" --format "${args[@]}" >/dev/null 2>&1) || true
}

# editorconfig_max_line_length <dir>: the max_line_length the project's .editorconfig files
# give Kotlin files in <dir>, or nothing if none sets it. Mirrors EditorConfig lookup: files
# from <dir> up to the filesystem root, stopping after one with root = true; nearer files
# win, and later sections win within a file. Sections that can match a .kt file count:
# [*], or any glob naming kt (such as [*.{kt,kts}] or [*.kt]).
editorconfig_max_line_length() {
  local dir files=() value=""
  dir=$(cd "$1" && pwd)
  while :; do
    if [[ -f $dir/.editorconfig ]]; then
      files=("$dir/.editorconfig" "${files[@]}")   # farthest first, so nearer files override
      grep -qiE '^[[:space:]]*root[[:space:]]*=[[:space:]]*true' "$dir/.editorconfig" && break
    fi
    [[ $dir == / || $dir == "${dir%/*}" || -z $dir ]] && break
    dir=${dir%/*}; [[ -z $dir ]] && dir=/
  done
  for f in "${files[@]}"; do
    v=$(tr -d '\r' <"$f" | awk '
      /^[[:space:]]*\[/ { s = $0; gsub(/[[:space:]]/, "", s); applies = (s == "[*]" || s ~ /kt/); next }
      applies && tolower($0) ~ /^[[:space:]]*max_line_length[[:space:]]*=/ {
        v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*([#;].*)?$/, "", v); found = v
      }
      END { if (found != "") print tolower(found) }')
    [[ -n $v ]] && value=$v
  done
  echo "$value"
}

# detekt_line_length_config <dir> <out.yml>: when the project's .editorconfig sets
# max_line_length, write a detekt config that makes MaxLineLength follow it ("off" turns the
# rule off). Prints the path, or nothing when the project does not set it.
detekt_line_length_config() {
  local value
  value=$(editorconfig_max_line_length "$1")
  case $value in
    off | unset) printf 'style:\n  MaxLineLength:\n    active: false\n' >"$2" ;;
    '' ) return 0 ;;
    *[!0-9]*) return 0 ;;   # not a number: leave detekt's default
    *) printf 'style:\n  MaxLineLength:\n    active: true\n    maxLineLength: %s\n' "$value" >"$2" ;;
  esac
  echo "$2"
}

# lint_detekt <out> <dir>
lint_detekt() {
  local out=$1 input=$2 raw="$1.raw" base root config
  base=${BASE:-$ROOT}
  root=$(native "$base")
  rm -f "$raw" "$out.xml"
  # config/detekt.yml, then the project's line length on top (#3: one setting for both engines).
  config=$(native "$DETEKT_CONFIG")
  if [[ -d $base/$input ]] && extra=$(detekt_line_length_config "$base/$input" "$out.line-length.yml") && [[ -n $extra ]]; then
    config="$config,$(native "$extra")"
  fi
  (cd "$base" && java -jar "$DETEKT" --input "$input" --base-path "$root" --excludes "$EXCLUDES" \
    --config "$config" --build-upon-default-config \
    --report "txt:$(native "$raw")" --report "xml:$(native "$out.xml")" >"$out.log" 2>&1) || true
  # No report means detekt did not run; never read that as "0 findings".
  if [[ ! -f $raw ]]; then
    echo "detekt produced no report for $input:" >&2
    cat "$out.log" >&2
    exit 3
  fi
  sed -E -e 's/ - Signature=.*$//' -e 's|\\|/|g' -e "s|$root/||" -e "s|$base/||" "$raw" \
    | grep -v '^$' >"$out" || true
}

# bug_rules: the rule tags (as printed in [brackets], e.g. detekt:SwallowedException or
# compose:lambda-param-in-effect) that config/bug-rules.txt names. detekt-set:<name> lines
# expand to every rule in that set of the pinned detekt's own default config. Cached.
bug_rules() {
  local cached=$CACHE/bug-rules-$DETEKT_VERSION-$(sha256 "$ROOT/config/bug-rules.txt" | cut -c1-12).txt jar=jar tmp sets
  if [[ ! -f $cached ]]; then
    [[ -n ${JAVA_HOME:-} && -x $JAVA_HOME/bin/jar ]] && jar=$JAVA_HOME/bin/jar
    tmp=$(mktemp -d)
    (cd "$tmp" && "$jar" xf "$(native "$DETEKT")" default-detekt-config.yml)
    sets=$(tr -d '\r' <"$ROOT/config/bug-rules.txt" | sed -n 's/^detekt-set:\([a-z-]*\).*/\1/p' | tr '\n' ' ')
    {
      awk -v sets=" $sets " '
        /^[a-z-]+:[[:space:]]*$/ { set = $1; sub(/:.*/, "", set); next }
        /^  [A-Za-z]+:[[:space:]]*$/ && index(sets, " " set " ") { r = $1; sub(/:.*/, "", r); print "detekt:" r }
      ' "$tmp/default-detekt-config.yml"
      tr -d '\r' <"$ROOT/config/bug-rules.txt" | sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep -E '^[a-z]+:' | grep -v '^detekt-set:'
    } | LC_ALL=C sort -u >"$cached.part"
    rm -rf "$tmp"
    mv "$cached.part" "$cached"
  fi
  cat "$cached"
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
