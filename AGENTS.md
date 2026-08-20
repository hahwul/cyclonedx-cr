# AGENTS.md

This file contains instructions for AI agents working on the `cyclonedx-cr` project.

## Project Overview

`cyclonedx-cr` is a Crystal application that generates CycloneDX Software Bill of Materials (SBOM) from `shard.yml` and `shard.lock` files.

- **Language:** Crystal
- **Build System:** Shards
- **Spec Versions:** CycloneDX 1.4, 1.5, 1.6, 1.7 (1.6 is the default)
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

`spec/app_integration_spec.cr` drives the compiled `./bin/cyclonedx-cr`, not the
library, so **run `shards build` before `crystal spec`** after touching `src/`.
The suite aborts with a reminder rather than reporting the previous build's
behaviour as a regression.

#### Schema-validation specs

Generated documents are validated against the official CycloneDX schemas
vendored in `spec/schemas/` — the XSDs via `xmllint` and the JSON schemas via
`check-jsonschema`. Both tools are **optional**: examples needing a missing one
are marked pending, so an incomplete local setup looks like a passing run.

```bash
# macOS: xmllint ships with the OS; install the JSON validator with
uv tool install check-jsonschema   # or: pipx install check-jsonschema
```

A full run takes roughly 8 seconds. A sub-second run means the schema examples
were skipped, so **never conclude that a serialization or version-gating change
is correct from a fast suite**.

### Spec-version gating

`src/cyclonedx/version_gate.cr` is the single source of truth for what each
CycloneDX version permits, covering fields, enum values and repeated-element
shapes. Two invariants it relies on:

- `BOM#to_json(JSON::Builder)` is the only JSON entry point, and it reaches the
  generated serializer with `super`. `super` works only inside the overriding
  method, so this cannot be refactored into a helper.
- `Validator` does not re-derive the gating rules; `VersionGate.violations` runs
  the filter and reports what it changed. Add a gated field to the tables and it
  is reported automatically — do not write a parallel traversal.

Repairable downgrades are `Validator#warnings` (the output is still valid); only
what the gate cannot repair is an error. Enum tables are cross-checked against
the XSDs by `spec/cyclonedx/enum_consistency_spec.cr`, so derive enum edits from
the schemas rather than editing the lists by hand.

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
