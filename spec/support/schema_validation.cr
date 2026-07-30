require "spec"

# Shared helpers for validating generated BOMs against the *official* CycloneDX
# schemas vendored under `spec/schemas/`.
#
# Both validators are external tools and both are optional: when one is missing
# the examples that use it are marked pending rather than failing, so the suite
# still runs on a bare machine. CI installs both (see `.github/workflows/ci.yml`)
# so the coverage is real there.
module SchemaValidation
  extend self

  SCHEMA_DIR = File.expand_path(File.join(__DIR__, "..", "schemas"))

  # Every spec version the library claims to support. Schema-validation specs
  # iterate this so a newly supported version cannot be added without also
  # being validated.
  VERSIONS = CycloneDX::BOM::SUPPORTED_VERSIONS

  XMLLINT = Process.find_executable("xmllint")

  # `check-jsonschema` (pip) is preferred; `ajv` (npm) is accepted as a
  # fallback. Both resolve the schemas' relative `$ref`s against SCHEMA_DIR.
  JSON_VALIDATOR = Process.find_executable("check-jsonschema")

  def schema_path(name : String) : String
    File.join(SCHEMA_DIR, name)
  end

  # Validates `xml` against the bundled `bom-<version>.xsd`, returning
  # {success, stderr}. `catalog.xml` maps the schemas' remote SPDX import to the
  # local copy.
  def xsd_validate(xml : String, version : String) : {Bool, String}
    run_validator(xml, ".xml", "xmllint",
      ["--noout", "--schema", schema_path("bom-#{version}.xsd")],
      {"XML_CATALOG_FILES" => schema_path("catalog.xml")})
  end

  # Validates `json` against the bundled `bom-<version>.schema.json`, returning
  # {success, stderr}.
  def json_schema_validate(json : String, version : String) : {Bool, String}
    run_validator(json, ".json", "check-jsonschema",
      ["--schemafile", schema_path("bom-#{version}.schema.json")], nil)
  end

  private def run_validator(document : String, suffix : String, command : String,
                            args : Array(String), env : ::Hash(String, String)?) : {Bool, String}
    tmp = File.tempfile("cdx-schema", suffix)
    begin
      File.write(tmp.path, document)
      err = IO::Memory.new
      status = Process.run(command, args + [tmp.path], env: env,
        output: Process::Redirect::Close, error: err)
      {status.success?, err.to_s}
    ensure
      tmp.delete
    end
  end
end

# Asserts `bom` validates against both official schemas for its declared spec
# version. Skips whichever validator is unavailable.
def assert_schema_valid(bom : CycloneDX::BOM, label : String)
  version = bom.spec_version

  if SchemaValidation::XMLLINT
    ok, err = SchemaValidation.xsd_validate(bom.to_xml, version)
    fail("#{label}: bom-#{version}.xsd validation failed:\n#{err}") unless ok
  end

  if SchemaValidation::JSON_VALIDATOR
    ok, err = SchemaValidation.json_schema_validate(bom.to_json, version)
    fail("#{label}: bom-#{version}.schema.json validation failed:\n#{err}") unless ok
  end

  if SchemaValidation::XMLLINT.nil? && SchemaValidation::JSON_VALIDATOR.nil?
    pending!("neither xmllint nor check-jsonschema is installed")
  end
end
