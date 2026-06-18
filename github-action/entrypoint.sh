#!/bin/sh -l

# GitHub Action inputs with defaults
SHARD_FILE=${1:-shard.yml}
LOCK_FILE=${2:-shard.lock}
OUTPUT_FILE=$3
SPEC_VERSION=${4:-1.6}
OUTPUT_FORMAT=${5:-json}

# Validate inputs
if [ ! -f "$SHARD_FILE" ]; then
    echo "Error: Shard file '$SHARD_FILE' not found"
    exit 1
fi

if [ ! -f "$LOCK_FILE" ]; then
    echo "Error: Lock file '$LOCK_FILE' not found"
    exit 1
fi

# Find cyclonedx-cr binary
if command -v cyclonedx-cr >/dev/null 2>&1; then
    CYCLONEDX_BIN="cyclonedx-cr"
elif [ -f "/usr/local/bin/cyclonedx-cr" ]; then
    CYCLONEDX_BIN="/usr/local/bin/cyclonedx-cr"
elif [ -f "/usr/bin/cyclonedx-cr" ]; then
    CYCLONEDX_BIN="/usr/bin/cyclonedx-cr"
else
    echo "Error: cyclonedx-cr binary not found"
    exit 1
fi

# Handle output file
if [ -n "$OUTPUT_FILE" ]; then
    OUTPUT_TO_FILE=true
else
    OUTPUT_FILE=$(mktemp)
    OUTPUT_TO_FILE=false
fi

# Cleanup temp file on exit
if [ "$OUTPUT_TO_FILE" = "false" ]; then
    trap "rm -f '$OUTPUT_FILE'" EXIT
fi

# Execute the command
if ! "$CYCLONEDX_BIN" -s "$SHARD_FILE" -i "$LOCK_FILE" --spec-version "$SPEC_VERSION" --output-format "$OUTPUT_FORMAT" -o "$OUTPUT_FILE"; then
    echo "Error: cyclonedx-cr command failed"
    exit 1
fi

# Verify output file exists
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file '$OUTPUT_FILE' not found"
    exit 1
fi

# Emits a random hex token suitable for a unique GitHub Actions heredoc
# delimiter. Prefers the kernel UUID source (present on Linux runners without
# any extra package), then /dev/urandom; the final fallback is non-random but
# the caller's collision check still guarantees a correct delimiter.
gen_delimiter() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        printf 'cdx_%s' "$(tr -d '-' < /proc/sys/kernel/random/uuid)"
    elif [ -r /dev/urandom ]; then
        printf 'cdx_%s' "$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    else
        printf 'cdx_%s_%s' "$$" "$(date +%s 2>/dev/null || echo 0)"
    fi
}

# Set GitHub Action outputs
if [ -n "$GITHUB_OUTPUT" ]; then
    if [ "$OUTPUT_TO_FILE" = "true" ]; then
        echo "sbom_file=$OUTPUT_FILE" >> "$GITHUB_OUTPUT"
        echo "Generated SBOM file: $OUTPUT_FILE"
    else
        # Emit multiline SBOM content with a RANDOM heredoc delimiter. A fixed
        # delimiter (the old `EOF`) is unsafe: GitHub ends the value at the
        # first line that equals the delimiter, so attacker-controlled SBOM
        # content -- e.g. a multiline dependency name that yields a bare `EOF`
        # line in CSV output -- could terminate `sbom_content` early and inject
        # arbitrary additional step outputs. The delimiter is re-rolled until it
        # does not appear as a whole line in the content. See issue #70.
        delimiter=$(gen_delimiter)
        while grep -qxF -- "$delimiter" "$OUTPUT_FILE"; do
            delimiter=$(gen_delimiter)
        done
        {
            printf 'sbom_content<<%s\n' "$delimiter"
            cat "$OUTPUT_FILE"
            # Guarantee the closing delimiter lands on its own line even when the
            # content has no trailing newline (e.g. JSON output), otherwise the
            # delimiter would be glued to the last content line and never match.
            [ -n "$(tail -c1 "$OUTPUT_FILE")" ] && printf '\n'
            printf '%s\n' "$delimiter"
        } >> "$GITHUB_OUTPUT"
        echo "Generated SBOM content (captured to output)"
    fi
fi

echo "cyclonedx-cr GitHub Action completed successfully"
