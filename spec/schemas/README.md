# Bundled CycloneDX XSD schemas

Vendored copies of the official CycloneDX XML schemas (1.4 / 1.5 / 1.6) and the
SPDX schema they import, from https://github.com/CycloneDX/specification. They
are used by `spec/cyclonedx/schema_validation_spec.cr` to validate generated XML
against the real schema (via `xmllint`). `catalog.xml` maps the
`http://cyclonedx.org/schema/spdx` import to the local `spdx.xsd`.
