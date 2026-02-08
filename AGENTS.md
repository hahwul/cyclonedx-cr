# AGENTS.md

This file contains instructions for AI agents working on the `cyclonedx-cr` project.

## Project Overview

`cyclonedx-cr` is a Crystal application that generates CycloneDX Software Bill of Materials (SBOM) from `shard.yml` and `shard.lock` files.

- **Language:** Crystal
- **Build System:** Shards
- **Spec Versions:** CycloneDX 1.4, 1.5, 1.6, 1.7
- **Output Formats:** JSON, XML, CSV

## Directory Structure

- `src/`: Source code for the application.
  - `src/cyclonedx/`: Logic for generating BOM and Component objects.
  - `src/shard/`: Parsers for `shard.yml` and `shard.lock`.
- `spec/`: Crystal specs (tests).
- `bin/`: Compiled binary location (after build).
- `.github/`: GitHub Actions workflows.

## Development Workflow

### Prerequisites

Ensure Crystal and Shards are installed.

### Dependencies

To install dependencies:
```bash
shards install
```

### Building

To build the project:
```bash
shards build
```
The binary will be created at `./bin/cyclonedx-cr`.

**Note:** The `Dockerfile` in this repository is known to fail due to missing `liblzma-dev` dependencies required for static linking. For development, use the native `shards build` command instead of Docker.

### Testing

To run the test suite:
```bash
crystal spec
```
All new features or bug fixes must include corresponding specs.

### Running

To run the application from source:
```bash
crystal run src/main.cr -- [arguments]
```
Or use the built binary:
```bash
./bin/cyclonedx-cr [arguments]
```

### Formatting

Code should be formatted using the standard Crystal formatter:
```bash
crystal tool format
```

## Contribution Guidelines

- Follow standard Crystal style conventions.
- Update `shard.yml` version if necessary.
- Ensure all tests pass before submitting changes.
