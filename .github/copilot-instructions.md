# cyclonedx-cr (Crystal)

cyclonedx-cr is a command-line tool written in Crystal that generates CycloneDX Software Bill of Materials (SBOM) from Crystal shard files (shard.yml and shard.lock). It outputs SBOM data in JSON, XML, or CSV formats with support for CycloneDX spec versions 1.4, 1.5, and 1.6.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

- Install Crystal and dependencies:
  - `sudo apt-get update && sudo apt-get install -y crystal shards`
  - Crystal version 1.11.2+ is tested and working
  - Shards is Crystal's package manager and build tool

- Bootstrap and build the repository:
  - `shards install` -- takes <1 second. Dependencies are minimal.
  - `shards build` -- takes 4 seconds. NEVER CANCEL. Set timeout to 60+ seconds for safety.

- Run tests:
  - `crystal spec` -- takes 4 seconds. NEVER CANCEL. Set timeout to 30+ seconds for safety.

- Run the application:
  - ALWAYS run `shards build` first to create the `bin/cyclonedx-cr` binary
  - Basic usage: `./bin/cyclonedx-cr` (processes shard.yml and shard.lock in current directory)
  - View help: `./bin/cyclonedx-cr --help`
  - Specify files: `./bin/cyclonedx-cr -s shard.yml -i shard.lock`
  - Change output format: `./bin/cyclonedx-cr --output-format xml` (options: json, xml, csv)
  - Specify CycloneDX version: `./bin/cyclonedx-cr --spec-version 1.5` (options: 1.4, 1.5, 1.6)

## Validation

- Always manually validate any changes by running the application with different output formats:
  - `./bin/cyclonedx-cr --output-format json`
  - `./bin/cyclonedx-cr --output-format xml`  
  - `./bin/cyclonedx-cr --output-format csv`

- ALWAYS run through at least one complete end-to-end scenario after making changes:
  - Build the project: `shards build`
  - Test basic functionality: `./bin/cyclonedx-cr --help`
  - Generate SBOM: `./bin/cyclonedx-cr --output-format json -o test-output.json`
  - Verify output file was created and contains valid SBOM data

- The application requires shard.yml and shard.lock files to be present in the working directory
- Use the project's own shard.yml and shard.lock for testing (they always exist)

## Common Tasks

### Development Build Cycle
- `shards install` (if dependencies changed)
- `shards build` 
- `crystal spec` (run tests)
- `./bin/cyclonedx-cr --help` (verify binary works)

### Testing Different Output Formats
- JSON (default): `./bin/cyclonedx-cr`
- XML: `./bin/cyclonedx-cr --output-format xml`
- CSV: `./bin/cyclonedx-cr --output-format csv`

### Docker Build (Has Known Issues)
- `docker build -t cyclonedx-cr .` -- FAILS due to missing liblzma-dev dependency in static linking
- The Dockerfile attempts to create a static binary but lacks the liblzma-dev package
- Takes ~30 seconds before failing. NEVER CANCEL. Set timeout to 120+ seconds.
- For development, use native Crystal build instead of Docker

## Project Structure

### Key Directories and Files
```
/home/runner/work/cyclonedx-cr/cyclonedx-cr/
├── shard.yml                    # Project metadata
├── shard.lock                   # Locked dependencies  
├── src/
│   ├── main.cr                  # Entry point
│   ├── app.cr                   # Main application logic and CLI parsing
│   ├── cyclonedx/
│   │   ├── bom.cr              # CycloneDX BOM class with JSON/XML/CSV serialization
│   │   └── component.cr        # CycloneDX Component class
│   └── shard/
│       ├── shard_file.cr       # Shard.yml parser
│       └── shard_lock_file.cr  # Shard.lock parser
├── spec/
│   └── main_spec.cr            # Basic test file
├── bin/                        # Generated binary location (after shards build)
├── .github/workflows/          # CI/CD configuration
└── Dockerfile                  # Docker build (has static linking issues)
```

### Frequently Modified Files
- When changing CLI options: edit `src/app.cr` (OptionParser configuration)
- When changing SBOM output: edit `src/cyclonedx/bom.cr` or `src/cyclonedx/component.cr`
- When changing file parsing: edit `src/shard/shard_file.cr` or `src/shard/shard_lock_file.cr`
- Always update tests in `spec/main_spec.cr` when adding new functionality

## CI/CD Integration

The project uses GitHub Actions with the following jobs:
- **build-crystal**: Tests multiple Crystal versions (1.14.1, 1.15.0, 1.16.0, 1.17.0)
- **build-docker**: Builds Docker images for linux/amd64 and linux/arm64
- **lint**: Uses Crystal Ameba linter (ameba is not installed locally by default)  
- **tests**: Runs `crystal spec` in Docker container

Always ensure your changes work with:
- `shards build` (builds successfully)
- `crystal spec` (tests pass)
- Manual validation with different output formats

## Command Reference

### Successful Commands (Validated Working)
```bash
# Installation
sudo apt-get update && sudo apt-get install -y crystal shards

# Build and test cycle  
shards install        # <1 second
shards build          # 4 seconds  
crystal spec          # 4 seconds

# Application usage
./bin/cyclonedx-cr --help
./bin/cyclonedx-cr --output-format json
./bin/cyclonedx-cr --output-format xml  
./bin/cyclonedx-cr --output-format csv
./bin/cyclonedx-cr --spec-version 1.5 --output-format json -o output.json
```

### Known Failing Commands
```bash
# Docker build fails due to missing liblzma-dev for static linking
docker build -t cyclonedx-cr .  # FAILS after ~30 seconds

# Ameba linter not available locally (works in CI only)
ameba  # Command not found locally
```

### Expected Output Samples
- Help command shows all CLI options including input/output files, formats, and spec versions
- JSON output: `{"bomFormat":"CycloneDX","specVersion":"1.6","version":1,"components":[...]}`
- XML output: `<?xml version="1.0"?><bom xmlns="http://cyclonedx.org/schema/bom/1.6"...>`
- CSV output: Headers `Name,Version,PURL,Type` followed by component data

## Troubleshooting

### Build Issues
- If `crystal: command not found`: Install with `sudo apt-get install -y crystal`
- If `shards: command not found`: Install with `sudo apt-get install -y shards`  
- If build fails with missing libraries: Crystal requires development headers for linked libraries

### Runtime Issues  
- If "shard.yml not found": The tool requires shard.yml and shard.lock files in the working directory
- If "Invalid spec version": Only 1.4, 1.5, and 1.6 are supported
- If "Invalid output format": Only json, xml, and csv are supported

### Docker Issues
- Static linking fails due to missing liblzma-dev in the 84codes/crystal container
- For development, use native Crystal build instead of Docker build
- Container builds work for CI/CD but not for static binary generation