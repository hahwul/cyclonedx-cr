#!/bin/sh
# Regression test for issue #70: GitHub Action output injection via a fixed
# GITHUB_OUTPUT heredoc delimiter.
#
# It crafts a shard.lock whose dependency name contains newlines forming a bare
# "EOF" line (the old fixed delimiter) plus an "injected=pwned" line, runs the
# real entrypoint in each output format with no output_file, and asserts that:
#   1. no step output is created outside the sbom_content heredoc value
#      (i.e. the malicious content cannot inject step outputs), and
#   2. the heredoc is well-formed (a closing delimiter line exists), so the
#      value is not silently truncated or left unterminated.
#
# Run from anywhere after `shards build`:  ./github-action/test-entrypoint.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BIN_DIR="$REPO_ROOT/bin"
if [ ! -x "$BIN_DIR/cyclonedx-cr" ]; then
    echo "FAIL: $BIN_DIR/cyclonedx-cr not built (run 'shards build' first)" >&2
    exit 1
fi
PATH="$BIN_DIR:$PATH"
export PATH

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/shard.yml" <<'YML'
name: victim
version: 1.0.0
YML

# The dependency NAME (a YAML key) carries embedded newlines: a bare "EOF" line
# and an "injected=pwned" line an attacker hopes to surface as a step output.
printf 'version: 2.0\nshards:\n  "evil\\nEOF\\ninjected=pwned\\ntail":\n    github: a/b\n    version: 9.9.9\n' > "$WORK/shard.lock"

# Counts step outputs declared OUTSIDE any heredoc value. POSIX awk only
# (mawk-compatible: no gawk 3-arg match / gensub).
count_injected() {
    awk '
        # Heredoc opener: key<<DELIM. Only recognised when NOT already inside a
        # heredoc -- once inside, every line is content until the delimiter,
        # exactly as the GitHub command-file parser behaves.
        !inhd && /^[A-Za-z_][A-Za-z0-9_-]*<<.+$/ {
            i = index($0, "<<")
            delim = substr($0, i + 2)
            inhd = 1
            next
        }
        inhd && $0 == delim { inhd = 0; closed = 1; next }
        # A key=value line outside a heredoc is a (possibly injected) output.
        !inhd && /^[A-Za-z_][A-Za-z0-9_-]*=/ { injected++ }
        END {
            # closed must be 1 (heredoc terminated) and injected must be 0.
            print (injected + 0) " " (closed + 0)
        }
    ' "$1"
}

rc=0
for fmt in json xml csv; do
    out="$WORK/gh_output.$fmt"
    : > "$out"
    GITHUB_OUTPUT="$out" sh "$SCRIPT_DIR/entrypoint.sh" \
        "$WORK/shard.yml" "$WORK/shard.lock" "" 1.6 "$fmt" >/dev/null

    set -- $(count_injected "$out")
    injected=$1
    closed=$2

    if [ "$injected" != "0" ]; then
        echo "FAIL [$fmt]: $injected step output(s) injected outside sbom_content" >&2
        rc=1
    elif [ "$closed" != "1" ]; then
        echo "FAIL [$fmt]: sbom_content heredoc was not properly closed" >&2
        rc=1
    else
        echo "PASS [$fmt]: no injection; heredoc well-formed"
    fi
done

exit "$rc"
