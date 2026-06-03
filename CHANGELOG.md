# Changelog

## Unreleased

### Fixed
- PURLs are now percent-encoded per the package-url spec. Reserved characters
  in the namespace/name and version (space, `+`, `@`, `&`, `#`, ...) are
  encoded, so git-resolved versions like `0.1.0+git.commit.<sha>` produce a
  valid `pkg:...@0.1.0%2Bgit.commit.<sha>` instead of a malformed PURL.
- PURL namespace/name are lowercased for the case-insensitive `github` and
  `bitbucket` types (e.g. `pkg:github/sysexitcode/foo`), matching the canonical
  form used by other tooling. `gitlab` paths are case-sensitive and preserved.
- Git URLs with a trailing slash (e.g. `https://github.com/owner/repo/`) now
  yield a PURL instead of none.
- GitLab subgroup git URLs (`gitlab.com/group/subgroup/repo`) now produce a
  full-path PURL, consistent with the explicit `gitlab:` key.
- Bitbucket git URLs now produce `pkg:bitbucket/...` PURLs.
- A free-form license string that merely contains `AND`/`OR`/`WITH` (e.g.
  "Free for personal OR commercial use") is no longer mis-emitted as an invalid
  SPDX `expression`; it now falls back to a `license.name`. Only strings that
  parse as a valid SPDX expression become a `LicenseExpression`.
- XML element ordering now matches the CycloneDX XSD `<sequence>` for both
  `component` (hashes/licenses before copyright/cpe/purl; pedigree before
  externalReferences; components before evidence; releaseNotes before modelCard)
  and `metadata` (lifecycles immediately after timestamp). Previously the output
  could fail XSD validation.
- Spec-version gating now strips the 1.6-only `bom-ref`/`acknowledgement` from a
  `LicenseExpression` in both JSON and XML, so a 1.4/1.5 BOM no longer leaks
  1.6-only fields (the `Validator` already flagged them; the filters now agree).
- The dependency graph no longer contains a self-referential edge or duplicate
  entries when a locked dependency shares the project's `name@version`.
- Lock entries with an empty shard name are skipped with a warning instead of
  emitting a schema-invalid empty-name component.
- Stray positional arguments (e.g. a dropped dash in `spec-version 1.5`) are now
  rejected with an error instead of being silently ignored.
- License entries now follow the CycloneDX `LicenseChoice` shape:
  `{"license": {...}}` instead of a flat `{"id":"...","name":"..."}`.
  XML output already used `<license>...</license>` so this is a JSON-only
  fix that aligns with the 1.4–1.6 schemas.
- Removed the unsupported CycloneDX "1.7" spec version. 1.6 is the latest
  published spec; no validator accepts 1.7 and there is no 1.7 schema.
  Supported versions are now 1.4, 1.5, and 1.6 (default 1.6).
- `alg` (hash algorithm) and external-reference `type` are now validated
  against the CycloneDX enums in the model constructors.
- Version-less `path:` lock entries and version-less `shard.yml` no longer
  crash; `version` defaults to `"unknown"` when absent.
- `read_yaml_file` now distinguishes invalid YAML from a missing required
  attribute and reports an accurate error message for each.

### Changed
- License identifiers that exist in the SPDX license list are now emitted
  as the canonical SPDX `id` (e.g. `{"license":{"id":"MIT"}}`). Free-form
  values that are not in the SPDX list still fall through to `name`.
  Backed by a new dependency on `spdx.cr`.
- CSV output now includes the root application component (from
  `metadata.component`) as its first row, making it consistent with the
  JSON/XML output.

## v1.3.0

### Added
- Structural BOM validator with field path error reporting
- Annotations, formulation, and declarations support
- BOM JSON deserialization with comprehensive tests
- Pedigree and evidence support for supply chain transparency
- Provides field to Dependency for capability expression
- Compositions support for completeness assertions
- Services support for SaaSBOM
- Vulnerabilities support for VDR/VEX
- Properties support across BOM, Component, and Metadata

### Changed
- Expand Component model with missing spec fields
- Expand License model with text, bom-ref, and acknowledgement
- Expand Metadata model with lifecycles, manufacture, and supplier
- Improve code quality, validation, and test coverage
- Standardize CI workflow and remove ameba lint

### Fixed
- XML ordering, element names, and deserialization issues

## v1.2.0

### Added
- Executable entrypoints for `shards install` support
- `executables` field in `shard.yml` for shards install support
- CHANGELOG file

### Changed
- Remove old Crystal version CI
- Bump sigstore/cosign-installer from 4.0.0 to 4.1.1

### Fixed
- Fix version mismatch, harden entrypoint, and improve error handling

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
