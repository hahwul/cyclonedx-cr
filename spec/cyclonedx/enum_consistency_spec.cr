require "spec"
require "xml"
require "../../src/cyclonedx/bom"
require "../../src/cyclonedx/composition"
require "../support/schema_validation"

# Cross-checks every hand-maintained enum list in the object model, and every
# entry of `VersionGate`'s enum-version tables, against the vendored official
# XSDs.
#
# These lists are the kind of thing that rots quietly: a typo makes the library
# reject a value the spec permits *and* accept one it does not, and nothing else
# in the suite notices because the offending value is simply never exercised.
# (`risk-register` sat in `ExternalReference::VALID_TYPES` in place of the real
# `risk-assessment` for exactly that reason.) Deriving the expectations from the
# schemas themselves means adding a spec version cannot silently skip them.

private XS_NS = {"xs" => "http://www.w3.org/2001/XMLSchema"}

# The permitted values of a named XSD `simpleType` enumeration, in schema order.
private def xsd_enum(version : String, type_name : String) : Array(String)
  doc = XML.parse(File.read(SchemaValidation.schema_path("bom-#{version}.xsd")))
  doc.xpath_nodes(
    "//xs:simpleType[@name='#{type_name}']/xs:restriction/xs:enumeration/@value", XS_NS
  ).map(&.text)
end

# value => oldest supported spec version permitting it, derived from the XSDs.
private def introduced_in(type_name : String) : ::Hash(String, String)
  first = {} of String => String
  SchemaValidation::VERSIONS.each do |version|
    xsd_enum(version, type_name).each do |value|
      first[value] ||= version
    end
  end
  first
end

private OLDEST = SchemaValidation::VERSIONS.first

# Asserts `list` is exactly the union of `type_name`'s values across all
# supported versions, and that `gate_table` records the introducing version of
# every value that is not available in the oldest supported version.
private def assert_enum_matches_schema(list : Array(String), type_name : String,
                                       gate_table : ::Hash(String, String))
  introduced = introduced_in(type_name)

  list.sort.should eq(introduced.keys.sort!), <<-MSG
    #{type_name}: the model's value list does not match the union of the XSD enumerations.
      only in the model:  #{(list - introduced.keys).sort}
      only in the schema: #{(introduced.keys - list).sort}
    MSG

  expected_gates = introduced.reject { |_, version| version == OLDEST }
  gate_table.should eq(expected_gates), <<-MSG
    #{type_name}: VersionGate's version table disagrees with the XSDs.
      expected: #{expected_gates}
      actual:   #{gate_table}
    MSG
end

describe "enum lists vs. the official schemas" do
  it "matches component/@type (classification)" do
    assert_enum_matches_schema(
      CycloneDX::Component::VALID_TYPES, "classification",
      CycloneDX::VersionGate::COMPONENT_TYPE_VERSIONS)
  end

  it "matches externalReference/@type (externalReferenceType)" do
    assert_enum_matches_schema(
      CycloneDX::ExternalReference::VALID_TYPES, "externalReferenceType",
      CycloneDX::VersionGate::EXTERNAL_REFERENCE_TYPE_VERSIONS)
  end

  it "matches composition/aggregate (aggregateType)" do
    assert_enum_matches_schema(
      CycloneDX::Composition::VALID_AGGREGATES, "aggregateType",
      CycloneDX::VersionGate::AGGREGATE_VERSIONS)
  end

  it "matches hash/@alg (hashAlg)" do
    assert_enum_matches_schema(
      CycloneDX::Hash::VALID_ALGORITHMS, "hashAlg",
      CycloneDX::VersionGate::HASH_ALG_VERSIONS)
  end

  it "matches component/scope (scope)" do
    xsd_enum(SchemaValidation::VERSIONS.last, "scope")
      .sort.should eq(CycloneDX::Component::VALID_SCOPES.sort)
  end

  it "gates every enum value that has a designated catch-all to a real value" do
    # A downgrade target must itself be permitted in the oldest version,
    # otherwise the gate would swap one invalid value for another.
    CycloneDX::VersionGate::ENUM_FALLBACK.each do |_, keys|
      keys.each_value do |fallback|
        permitted = xsd_enum(OLDEST, "externalReferenceType") +
                    xsd_enum(OLDEST, "aggregateType")
        permitted.should contain(fallback)
      end
    end
  end

  it "covers every supported spec version in VERSION_ORDER" do
    CycloneDX::VersionGate::VERSION_ORDER.keys.sort!
      .should eq(SchemaValidation::VERSIONS.sort)
  end

  it "ships an XSD and a JSON schema for every supported spec version" do
    SchemaValidation::VERSIONS.each do |version|
      File.exists?(SchemaValidation.schema_path("bom-#{version}.xsd")).should be_true
      File.exists?(SchemaValidation.schema_path("bom-#{version}.schema.json")).should be_true
    end
  end
end
