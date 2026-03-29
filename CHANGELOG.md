# Changelog

## v1.1.0

### Added
- Metadata support and enriched component details in SBOM
- Tests for CycloneDX::Metadata, CycloneDX::License, CycloneDX::Component, ShardFile, and ShardLockFile
- Executable script `cyclonedx-cr.cr` for dependency usage
- Dependabot configuration for GitHub Actions and Docker
- AGENTS.md for development instructions

### Changed
- Refactor file parsing to use streaming for reduced memory usage
- Refactor file reading and parsing to handle exceptions gracefully
- Refactor `App#run` to exit with error code on validation failure
- Ensure consistent BOM serial number across formats
- Bump docker actions (build-push-action v7, metadata-action v6, login-action v4, setup-buildx-action v4, setup-qemu-action v4)
- Bump sigstore/cosign-installer from 3.1.1 to 4.0.0
- Bump actions/checkout from 3 to 6
- Bump crystal-ameba/github-action from 0.8.0 to 0.12.0
- Bump Justintime50/homebrew-releaser from 1 to 3

### Fixed
- Bug fixes and lint improvements

## v1.0.2

### Changed
- Release maintenance

## v1.0.1

### Added
- CycloneDX spec version 1.7 support
- Nix flake support for package management

### Changed
- Refactor app.cr and cyclonedx classes for better readability
- Improve code quality with type safety and better patterns
- Extract regex patterns as constants for better maintainability
- Add dev_dependencies for ameba

## v1.0.0

### Changed
- Bump version to 1.0.0 and update dependencies

## v0.1.9

### Changed
- Update SBOM workflow to use explicit file mappings and new release action

## v0.1.8

### Changed
- Improve input validation and output handling in entrypoint.sh

## v0.1.7

### Changed
- Improve output handling in cyclonedx-cr

## v0.1.6

### Changed
- Release workflow update

## v0.1.5

### Changed
- Remove release workflow files for binaries and .deb packages
- Comment out non-root USER directive in Dockerfile

## v0.1.4

### Added
- LICENSE file

## v0.1.3

### Changed
- Remove static linking from Crystal build commands

## v0.1.2

### Added
- Workflow to generate and upload SBOM on release
- Missing build dependencies to Docker build steps

## v0.1.1

### Changed
- Use double quotes for all default values and descriptions in action.yml
- Update build scripts to use src/main.cr as entry point

## v0.1.0

### Added
- CycloneDX SBOM generator for Crystal projects
- Parse `shard.yml` and `shard.lock` for dependency analysis
- JSON, XML, and CSV output format support
- CycloneDX spec version selection (1.4, 1.5, 1.6)
- CLI with `--output`, `--format`, `--spec-version` options
- GitHub Action support with `action.yml`
- Dockerfile for building and running cyclonedx-cr
- CI workflow for Crystal build, Docker, lint, and tests
- GitHub Actions workflows for Docker image, Homebrew tap, binaries, and .deb packages
