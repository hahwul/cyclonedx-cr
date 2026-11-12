# cyclonedx-cr (Crystal)

A Crystal tool for generating [CycloneDX](https://cyclonedx.org/) Software Bill of Materials (SBOM) from Crystal shard projects.

## Features

- Generates CycloneDX SBOMs from Crystal `shard.yml` and `shard.lock` files
- Supports multiple output formats: JSON, XML, CSV
- Compatible with CycloneDX spec versions 1.4, 1.5, 1.6 and 1.7, validated against the official XSD *and* JSON schemas
- Emits output valid for the version you ask for: fields and enum values newer than the declared `specVersion` are stripped or downgraded, and the losses are reported
- Automatically generates canonical, percent-encoded Package URLs (PURLs) for GitHub, GitLab and Bitbucket dependencies, using the locked commit when it is not a released tag
- Records a `vcs` external reference for every dependency, including `codeberg:`, `hg:` and `fossil:` sources that have no PURL type
- Builds the real dependency graph, transitive edges included, from the installed shards' own `shard.yml`, and says honestly (via `compositions`) where it could not
- Reproducible output on request, for SBOMs that get committed, signed or diffed
- Docker support for containerized usage
- Fast and lightweight implementation in Crystal

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

### As a Shard Dependency

Add cyclonedx-cr to your `shard.yml`:

```yaml
development_dependencies:
  cyclonedx-cr:
    github: hahwul/cyclonedx-cr
```

Then run:

```bash
shards install
bin/cyclonedx-cr
```

### From Source

Requirements: [Crystal](https://crystal-lang.org/) 1.21.0+

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
    --reproducible                   Pin the timestamp and serial number so repeated runs over unchanged inputs produce identical output
    -h, --help                       Show this help
    -v, --version                    Show the version
```

### Reproducible output

By default every run gets a fresh `serialNumber` and the current time as its
`metadata.timestamp`, so two SBOMs for the same project never compare equal.
`--reproducible` pins both — the timestamp to the Unix epoch and the serial
number to the nil UUID — which is what you want when the SBOM is committed to the
repository, signed, or diffed between builds. The installed `lib/` is an input
too (it supplies the [dependency graph](#dependency-graph)), so generate the SBOM
after `shards install` everywhere you compare it:

```bash
cyclonedx-cr --reproducible -o sbom.json
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
        with:
          persist-credentials: false

      # Install the shards so the SBOM records the full dependency graph
      - name: Install Crystal
        uses: crystal-lang/install-crystal@v1
      # Only the shards' shard.yml files are read: skip their postinstall
      # scripts, which would otherwise run in a job holding a write token.
      - name: Install dependencies
        run: shards install --skip-postinstall --skip-executables

      # Generate SBOM using hahwul/cyclonedx-cr action
      - name: Generate SBOM
        uses: hahwul/cyclonedx-cr@v1.4.0
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
- the installed dependencies (`lib/`, or `SHARDS_INSTALL_PATH`) for a complete
  [dependency graph](#dependency-graph); without them each shard's edges are reported as `unknown`

Generate both by running `shards install` in your Crystal project. In CI, run it
before generating the SBOM.

## Output Formats

### JSON (Default)
Standard CycloneDX JSON format, suitable for most SBOM tools and platforms.

### XML
CycloneDX XML format, compatible with tools that require XML input.

### CSV
Simplified comma-separated values format for basic analysis and reporting, with
the columns `Name,Version,PURL,Type,Scope,BOM-Ref`. The first row is the root
component (from `metadata.component`), followed by one row per dependency.

Values beginning with `=`, `+`, `-` or `@` are prefixed with a single quote so
spreadsheet applications render them as text rather than evaluating them as
formulas.

## CycloneDX Specification Versions

- **1.7**: Newest published version (ECMA-424, 2nd edition)
- **1.6** (default): Widely supported; the safe choice for most tooling
- **1.5**: Stable version with broad tool compatibility
- **1.4**: Legacy version for compatibility with older tools

The default stays at 1.6 because tool support for it is the most universal.

CycloneDX added both fields *and* enum values over these versions, so asking for
an older `--spec-version` is a real downgrade rather than a relabelling. Anything
the requested version cannot express is handled before the document is written:

| Situation | What happens |
| --- | --- |
| A field newer than the declared version | stripped |
| An enum value newer than the declared version, where the enum has a catch-all | rewritten to that catch-all (`other`, `not_specified`) |
| An enum value newer than the declared version with no catch-all (`component/@type`) | reported as an error; nothing is written |
| A repeated element the older schema allows only once | collapsed to the first |

Whatever gets dropped or rewritten is reported on stderr, so a downgrade is never
silent. Every combination is checked against the official schemas in the test
suite (`spec/cyclonedx/schema_validation_spec.cr`).

## Dependency graph

`shard.lock` records *which* shards are installed but not which shard required
which. The edges come from the shards themselves: the root depends on the direct
`dependencies` and `development_dependencies` of `shard.yml`, and each locked
shard on the `dependencies` declared by its installed copy at
`lib/<name>/shard.yml` (or under `SHARDS_INSTALL_PATH` when set). Run
`shards install` first.

A shard reachable only through `development_dependencies` gets
`scope: optional`; anything a runtime dependency pulls in, directly or
transitively, stays `required`.

Each graph node is listed in a `compositions` entry saying how much is known
about its edges:

| `aggregate` | Meaning |
| --- | --- |
| `complete` | Every edge is recorded. |
| `incomplete` | The shard declares a dependency that is missing from `shard.lock` (an out-of-sync install). |
| `unknown` | The shard's `shard.yml` could not be read, so its edges are unknown. The shard is left out of the `dependencies` graph, since an empty `dependsOn` would claim it has none. |

Anything short of `complete` is also reported on stderr, including a shard whose
installed version (per `lib/.shards.info`) differs from the one `shard.lock` pins:
its edges would be the wrong ones, so they are reported as `unknown`. While part
of the runtime graph is unknown, only direct development dependencies are marked
`optional`: a transitive shard cannot be shown to be dev-only if an unseen edge
might reach it at runtime.

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
