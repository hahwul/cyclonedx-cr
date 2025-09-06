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

# Build the cyclonedx-cr command
cmd="$CYCLONEDX_BIN -s $SHARD_FILE -i $LOCK_FILE --spec-version $SPEC_VERSION --output-format $OUTPUT_FORMAT"

# Handle output file
if [ -n "$OUTPUT_FILE" ]; then
    cmd="$cmd -o $OUTPUT_FILE"
    OUTPUT_TO_FILE=true
else
    OUTPUT_FILE="/tmp/sbom_output"
    cmd="$cmd -o $OUTPUT_FILE"
    OUTPUT_TO_FILE=false
fi

echo "Executing command: $cmd"

# Execute the command
if ! eval "$cmd"; then
    echo "Error: cyclonedx-cr command failed"
    exit 1
fi

# Verify output file exists
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file '$OUTPUT_FILE' not found"
    exit 1
fi

# Set GitHub Action outputs
if [ "$OUTPUT_TO_FILE" = "true" ]; then
    echo "sbom_file=$OUTPUT_FILE" >> "$GITHUB_OUTPUT"
    echo "Generated SBOM file: $OUTPUT_FILE"
else
    # Use heredoc for multiline output to avoid delimiter issues
    {
        echo "sbom_content<<EOF"
        cat "$OUTPUT_FILE"
        echo "EOF"
    } >> "$GITHUB_OUTPUT"
    echo "Generated SBOM content (captured to output)"
fi

echo "cyclonedx-cr GitHub Action completed successfully"
