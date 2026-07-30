# Bundled CycloneDX schemas

Vendored copies of the official CycloneDX schemas for every spec version this
library supports (1.4 / 1.5 / 1.6 / 1.7), from
https://github.com/CycloneDX/specification:

| File | Used for |
| --- | --- |
| `bom-1.*.xsd` | XML validation via `xmllint` |
| `bom-1.*.schema.json` | JSON validation via `check-jsonschema` |
| `spdx.xsd`, `spdx.schema.json` | SPDX license enums imported by the above |
| `jsf-0.82.schema.json` | JSON Signature Format, referenced by `signature` |
| `cryptography-defs.schema.json` | crypto algorithm enums, referenced by 1.7 |
| `catalog.xml` | maps the XSDs' remote SPDX import to the local `spdx.xsd` |

`spec/cyclonedx/schema_validation_spec.cr` validates generated documents against
both schema families at every supported version, and
`spec/cyclonedx/enum_consistency_spec.cr` derives the expected enum values and
their introducing versions straight from the XSDs, so the hand-maintained lists
in `src/` cannot drift away from the spec.

Both validators are optional locally — examples needing a missing tool are
marked pending. CI installs both, so coverage is enforced there.

## Updating

Drop in the new files and add the version to
`CycloneDX::BOM::SUPPORTED_VERSIONS` and `VersionGate::VERSION_ORDER`; the
schema and enum-consistency specs then cover it automatically and will fail
until the enum tables are brought up to date.
