# cyclonedx-cr (Crystal)

A Crystal tool for generating [CycloneDX](https://cyclonedx.org/) Software Bill of Materials (SBOM) from Crystal shard projects.

## Features

- 🔍 Generates CycloneDX SBOMs from Crystal `shard.yml` and `shard.lock` files
- 📋 Supports multiple output formats: JSON, XML, CSV
- 📊 Compatible with CycloneDX spec versions 1.4, 1.5, 1.6, and 1.7
- 🔗 Automatically generates Package URLs (PURLs) for dependencies
- 🐳 Docker support for containerized usage
- ⚡ Fast and lightweight implementation in Crystal

## Installation

### Binary Releases

Download the latest binary from the [releases page](https://github.com/hahwul/cyclonedx-cr/releases).

### Homebrew (macOS/Linux)

```bash
brew install hahwul/cyclonedx-cr/cyclonedx-cr
```

### Docker

```bash
docker run --rm -v $(pwd):/workspace -w /workspace ghcr.io/hahwul/cyclonedx-cr:latest
```

### From Source

Requirements: [Crystal](https://crystal-lang.org/) 1.6.2+

```bash
git clone https://github.com/hahwul/cyclonedx-cr.git
cd cyclonedx-cr
shards install
shards build --release
```

## Usage

### Basic Usage

Generate an SBOM from your Crystal project:

```bash
cyclonedx-cr
```

This will read `shard.yml` and `shard.lock` from the current directory and output the SBOM to stdout in JSON format.

### Command Line Options

```bash
Usage: cyclonedx-cr [arguments]
    -i FILE, --input=FILE            shard.lock file path (default: shard.lock)
    -s FILE, --shard=FILE            shard.yml file path (default: shard.yml)
    -o FILE, --output=FILE           Output file path (default: stdout)
    --spec-version VERSION           CycloneDX spec version (options: 1.4, 1.5, 1.6, 1.7, default: 1.6)
    --output-format FORMAT           Output format (options: json, xml, csv, default: json)
    -h, --help                       Show this help
```

### Examples

#### Generate JSON SBOM to file
```bash
cyclonedx-cr -o sbom.json
```

#### Generate XML SBOM with specific spec version
```bash
cyclonedx-cr --output-format xml --spec-version 1.5 -o sbom.xml
```

#### Generate CSV SBOM from custom shard files
```bash
cyclonedx-cr -s my-shard.yml -i my-shard.lock --output-format csv -o sbom.csv
```

#### Docker usage
```bash
# Generate SBOM for current directory
docker run --rm -v $(pwd):/workspace -w /workspace ghcr.io/hahwul/cyclonedx-cr:latest -o sbom.json

# With custom shard files
docker run --rm -v $(pwd):/workspace -w /workspace ghcr.io/hahwul/cyclonedx-cr:latest \
  -s custom-shard.yml -i custom-shard.lock --output-format xml -o sbom.xml
```

#### GitHub Actions
```yaml
name: Generate and Upload SBOM

on:
  release:
    types: [created]

jobs:
  generate-sbom:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      # Checkout the repository code
      - name: Checkout code
        uses: actions/checkout@v4

      # Generate SBOM using hahwul/cyclonedx-cr action
      - name: Generate SBOM
        uses: hahwul/cyclonedx-cr@v1.0.0
        with:
          shard_file: ./shard.yml # Explicitly map to shard_file
          lock_file: ./shard.lock # Explicitly map to lock_file
          output_file: ./sbom.xml # Map to output_file
          output_format: xml # Map to output_format
          spec_version: 1.6 # Optional, specify if needed

      # Upload SBOM to GitHub Release
      - name: Upload SBOM to Release
        uses: softprops/action-gh-release@v2
        with:
          files: ./sbom.xml
          token: ${{ secrets.GITHUB_TOKEN }}

```

## Requirements

Your Crystal project must have:
- `shard.yml` file (project configuration)
- `shard.lock` file (locked dependency versions)

Generate the `shard.lock` file by running `shards install` in your Crystal project.

## Output Formats

### JSON (Default)
Standard CycloneDX JSON format, suitable for most SBOM tools and platforms.

### XML
CycloneDX XML format, compatible with tools that require XML input.

### CSV
Simplified comma-separated values format for basic analysis and reporting.

## CycloneDX Specification Versions

- **1.7**: Latest version with full feature support
- **1.6** (default): Latest stable version with broad compatibility
- **1.5**: Stable version with broad tool compatibility
- **1.4**: Legacy version for compatibility with older tools

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related Projects

- [CycloneDX](https://cyclonedx.org/) - OWASP CycloneDX SBOM Standard
- [Crystal](https://crystal-lang.org/) - The Crystal Programming Language
- [Shards](https://github.com/crystal-lang/shards) - Crystal Package Manager
