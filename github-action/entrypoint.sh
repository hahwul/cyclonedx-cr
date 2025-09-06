#!/bin/sh -l

# GitHub Action inputs:
# $1: shard_file
# $2: lock_file  
# $3: output_file
# $4: spec_version
# $5: output_format

# Set default values if empty
SHARD_FILE=${1:-shard.yml}
LOCK_FILE=${2:-shard.lock}
OUTPUT_FILE=$3
SPEC_VERSION=${4:-1.6}
OUTPUT_FORMAT=${5:-json}

# Build the cyclonedx-cr command  
# Try different possible locations for the cyclonedx-cr binary
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

cmd="$CYCLONEDX_BIN -s $SHARD_FILE -i $LOCK_FILE --spec-version $SPEC_VERSION --output-format $OUTPUT_FORMAT"

# Add output file if specified
if [ -n "$OUTPUT_FILE" ]; then
    cmd="$cmd -o $OUTPUT_FILE"
    OUTPUT_TO_FILE=true
else
    # Output to temporary file to capture for GitHub output
    OUTPUT_FILE="/tmp/sbom_output"
    cmd="$cmd -o $OUTPUT_FILE"
    OUTPUT_TO_FILE=false
fi

echo "Executing command: $cmd"

# Execute the command
eval "$cmd"

# Check if command was successful
if [ $? -ne 0 ]; then
    echo "Error: cyclonedx-cr command failed"
    exit 1
fi

# Check if the output file exists
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file $OUTPUT_FILE not found"
    exit 1
fi

# Set GitHub Action outputs
if [ "$OUTPUT_TO_FILE" = "true" ]; then
    # When outputting to file, set the file path
    echo "sbom_file=$OUTPUT_FILE" >> $GITHUB_OUTPUT
    echo "Generated SBOM file: $OUTPUT_FILE"
else
    # When outputting to stdout (captured in temp file), set the content
    sbom_content=$(cat "$OUTPUT_FILE")
    # For multiline output, we need to handle it properly for GitHub Actions
    {
        echo "sbom_content<<EOF"
        cat "$OUTPUT_FILE"
        echo "EOF"
    } >> $GITHUB_OUTPUT
    echo "Generated SBOM content (captured to output)"
fi

echo "cyclonedx-cr GitHub Action completed successfully"