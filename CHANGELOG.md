# Changelog

## v1.4.0

The theme of this release is spec fidelity. The official CycloneDX JSON schemas
and XSDs for 1.4–1.7 are now vendored into the test suite and every fixture —
plus a maximally-populated BOM — is validated against both schema families at
every supported version. That harness is what surfaced most of the fixes below.

### Added
- CycloneDX 1.7 (ECMA-424 2nd edition) support. The default stays 1.6. v1.3.0
  accepted `--spec-version 1.7`, but there was no 1.7 schema, field gate, or
  validator behind it; 1.7 is now a real target.
- `--reproducible` pins the BOM timestamp and serial number so repeated runs
  over unchanged inputs produce identical output — for SBOMs that get committed,
  signed, or diffed.
- `$schema` is now emitted in JSON output.
- Spec-version gating (`VersionGate`): fields *and* enum values newer than the
  declared `specVersion` are stripped or downgraded in both JSON and XML, so a
  document declaring 1.4/1.5 can no longer emit newer-than-declared content.
  `component/@type` grew from 8 permitted values in 1.4 to 13 in 1.6 and
  `externalReference/@type` from 16 to 47, so a structurally correct document
  could still fail validation. Values with a spec-designated catch-all are
  downgraded to it (`other`, `not_specified`), a too-new `hash/@alg` drops the
  hash, and `component/@type` — which has no catch-all — is reported rather than
  guessed at.
- Validator coverage for bom-ref uniqueness across the whole document, dangling
  dependency references (allowing `urn:cdx:` BOM-links), a license with neither
  id nor name, malformed timestamps and CPEs, and `componentData` types.
- Enum validation for `alg` (hash algorithm) and external-reference `type` in
  the model constructors.
- `Scope` and `BOM-Ref` columns in CSV output, appended after the original four
  so index-based consumers are unaffected.
- Prebuilt-binary Homebrew formula, published to the tap by a new release
  workflow that builds four platform binaries (macOS arm64/x86_64, Linux
  arm64/x86_64; Linux static musl). Previously the formula compiled from source
  on the user's machine.

### Changed
- The minimum Crystal version is now `>= 1.21.0` (was 1.6.2), matching what CI
  verifies.
- License identifiers that exist in the SPDX license list are now emitted as the
  canonical SPDX `id` (e.g. `{"license":{"id":"MIT"}}`). Free-form values that
  are not in the SPDX list still fall through to `name`. Backed by a new
  dependency on `spdx.cr`.
- License entries now follow the CycloneDX `LicenseChoice` shape:
  `{"license": {...}}` instead of a flat `{"id":"...","name":"..."}`. XML output
  already used `<license>...</license>`, so this is a JSON-only change that
  aligns with the 1.4–1.7 schemas.
- CSV output now includes the root application component (from
  `metadata.component`) as its first row, making it consistent with the
  JSON/XML output.
- The dependency graph is now declared `incomplete`: `shard.lock` cannot express
  transitive edges, so asserting a complete graph overstated what was known.
- The root component's `type` is derived from the presence of build targets, and
  all `shard.yml` authors are emitted as structured contacts.
- A lock entry with no version no longer carries a fabricated
  `version: "unknown"`. `version` is optional in every spec version, so an
  unknown version is an absent field rather than an invented one.
- Validator results are split into errors and warnings. A repaired version
  downgrade leaves the document schema-valid, so it is no longer a hard failure;
  only what the gate cannot repair is an error.
- The CLI runs `CycloneDX::Validator` before writing and fails loudly instead of
  emitting an invalid SBOM.
- Validator violations are derived by running the version gate and recording
  what it changed, instead of re-implementing the rules alongside it — the two
  had drifted apart.

### Fixed

PURL correctness — a PURL is an identity claim, so each of these mis-attributed
or malformed one:

- Forge-host matching searched the whole URL for `github.com` with no left
  boundary and no host anchoring, so `notgithub.com/o/r` and a mirror path like
  `mirror.internal/github.com/o/r` both produced `pkg:github/o/r`. Remotes are
  now split into `{host, path}` and the host compared, lowercased, against an
  exact host — which also fixes an uppercase `GITHUB.COM` silently losing its
  PURL, since hosts are case-insensitive per RFC 3986.
- A host `:port` was treated as the path separator, so
  `ssh://git@gitlab.com:22/group/repo` yielded `pkg:gitlab/22/group/repo`.
- `.git`-stripping and path cleanup only applied to the `git:` key, so
  `github: https://github.com/Owner/Repo` went into the PURL raw
  (`pkg:github/https%3A//github.com/owner/repo`) and `github: Owner/Repo/` left
  an empty path segment. Shorthands are now cleaned and validated; a malformed
  one gets a warning and no PURL, since a malformed PURL is worse than none.
- PURLs are now percent-encoded per the package-url spec. Reserved characters in
  the namespace/name and version (space, `+`, `@`, `&`, `#`, ...) are encoded,
  so git-resolved versions like `0.1.0+git.commit.<sha>` produce a valid
  `pkg:...@0.1.0%2Bgit.commit.<sha>`.
- The namespace/name are lowercased for the case-insensitive `github` and
  `bitbucket` types, matching the canonical form used by other tooling.
  `gitlab` paths are case-sensitive and preserved.
- A `?query`/`#fragment` in a git URL leaked into the PURL name (e.g.
  `repo.git%3Fref%3Dmain`) and left `.git` unstripped, or dropped the PURL
  entirely for `.git/?x=1`. Both are now stripped first.
- Git URLs with a trailing slash, GitLab subgroup URLs
  (`gitlab.com/group/subgroup/repo`), and Bitbucket git URLs now yield PURLs
  instead of none.
- The `bitbucket:` resolver now yields a PURL, and `codeberg:`/`hg:`/`fossil:`
  get a vcs external reference instead of having their source URL discarded.
- The locked commit SHA is used in the PURL when shards recorded
  `X+git.commit.<sha>`, which resolves to neither a tag nor a commit.

Schema validity:

- XML element ordering now matches the CycloneDX XSD `<sequence>` for the BOM
  root, `component` (hashes/licenses before copyright/cpe/purl; pedigree before
  externalReferences; components before evidence; releaseNotes before modelCard)
  and `metadata` (lifecycles immediately after timestamp).
- Every JSON entry point is gated. `to_pretty_json`, `to_json(IO)`, and nested
  serialization all bypassed the version filter and emitted 1.6 fields in a 1.4
  BOM; only the no-arg `to_json` was covered. Nested components (pedigree
  ancestry, tool components) are gated too.
- `component.data` is serialized as repeated `<data>` elements
  (`componentDataType`), not a `<data>` wrapper around `<dataset>`.
- `externalReference` accepted `risk-register`, which is not a CycloneDX value,
  and therefore rejected the real one, `risk-assessment`.
- License `bom-ref` was gated as 1.6-only but was introduced in 1.5; a valid 1.5
  license bom-ref is no longer stripped. The 1.6-only
  `bom-ref`/`acknowledgement` on a `LicenseExpression` are now stripped in both
  JSON and XML.
- `evidence.identity` is collapsed for 1.5, where it is a single object rather
  than an array.
- Library serializers that produced schema-invalid output are corrected against
  the official XSDs: `vulnerability` sequence order and the invalid `aliases`
  field; `service` tail order; `evidence` `occurrences` placement and the
  `<copyright>` wrapper; `declaration` `standards` placement and refLink
  emission; `annotation` subjects as `<subject ref="..."/>`; component
  `omniborId`/`swhid` in XML (previously JSON-only); a formulation step
  `command` as an object plus the required `taskTypes`; and `AttachedText` as
  `<attachment>`.
- A duplicate `bom-ref` when `shard.lock` re-lists the project (or a dependency
  shares the project's exact `name@version`) violated bom-ref uniqueness. The
  colliding lock entry is now dropped with a warning, and the dependency graph
  no longer contains a self-referential or duplicate edge.
- An scp-style `git@host:path` repository/homepage was emitted verbatim as an
  externalReference url, failing XSD anyURI validation. It is now normalized to
  `ssh://git@host/path`.
- `licenses` deserialization: `{"license":{"id":"MIT"}}` parsed into an all-nil
  `License` without raising and round-tripped to `{"license":{}}`, which no
  schema accepts.
- `components` is no longer required on input, and the 1.5+ object form of
  `metadata.tools` is supported — both made most third-party BOMs unreadable.
- The validator never structurally validated `metadata.component`, so an invalid
  root type/name/scope passed while the schema rejected it. A blank root name is
  now rejected the same way blank `shard.lock` entry names already were.

Licenses and scope:

- A free-form license string that merely contains `AND`/`OR`/`WITH` (e.g. "Free
  for personal OR commercial use"), or a grammatically valid expression of
  non-existent ids ("Foo AND Bar"), is no longer mis-emitted as an invalid SPDX
  `expression`; it falls back to a `license.name`. Deprecated and
  non-canonically-cased expressions are still kept as expressions.
- A shard declared in both `dependencies` and `development_dependencies` was
  emitted as `optional`. It is still required at runtime, so runtime membership
  now wins; reporting it as optional understated the scope of a runtime-reachable
  component in downstream triage.

Robustness:

- Version-less `path:` lock entries and a version-less `shard.yml` no longer
  crash.
- Lock entries with an empty shard name are skipped with a warning instead of
  emitting a schema-invalid empty-name component.
- Stray positional arguments (e.g. a dropped dash in `spec-version 1.5`) are
  rejected with an error instead of being silently ignored — including a bare
  `-`, which slipped past the flag filter.
- `read_yaml_file` distinguishes invalid YAML from a missing required attribute
  and reports an accurate error message for each.
- `ValidationError#to_s` was defined only in the no-arg form, so interpolating an
  error printed `#<CycloneDX::ValidationError:0x...>`; it is now `to_s(io)`.
- `spec/main_spec.cr` required `src/main.cr`, whose top level is `App.new.run`.
  That printed an SBOM into the spec output, and with `shard.lock` absent the
  load-time `exit(1)` aborted the whole suite before any example ran.

### Security
- The GitHub Action wrote `sbom_content` to `$GITHUB_OUTPUT` with a fixed
  heredoc delimiter (`EOF`). GitHub ends a heredoc at the first line equal to the
  delimiter and the content derives from repository-controlled files, so
  attacker-controlled multiline data could terminate `sbom_content` early and
  inject arbitrary additional step outputs — reachable with `output_format: csv`
  and no `output_file`, since a `shard.lock` dependency name can embed newlines
  that CSV quoting preserves. The delimiter is now a random per-invocation value,
  re-rolled until it does not appear as a whole line in the content, and the
  closing delimiter is guaranteed to be on its own line even when the content has
  no trailing newline (which also fixes a never-properly-closed heredoc for the
  default JSON output).
- The container image and Action now run as a non-root user (uid/gid 1001,
  matching the GitHub runner default). The base Dockerfile shipped with
  `USER 2:2` commented out, so SBOM output written into the bind-mounted
  `$GITHUB_WORKSPACE` ended up owned by root on the host runner.
- CSV values are copied verbatim from shard files, so a name like
  `=cmd|'/C calc'!A0` was evaluated as a formula when opened in Excel or Sheets.
  Such values are now quoted out.

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
