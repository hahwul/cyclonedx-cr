require "spec"
require "../../src/cyclonedx/evidence"

describe CycloneDX::EvidenceIdentity do
  it "serializes to JSON" do
    method = CycloneDX::EvidenceMethod.new(technique: "binary-analysis", confidence: 0.85)
    occurrence = CycloneDX::EvidenceOccurrence.new(location: "/lib/libcrypto.so")
    identity = CycloneDX::EvidenceIdentity.new(
      field: "name",
      confidence: 0.95,
      methods: [method],
      occurrences: [occurrence],
    )
    json = identity.to_json
    json.should contain(%("field":"name"))
    json.should contain(%("confidence"))
    json.should contain(%("methods"))
    json.should contain(%("binary-analysis"))
    json.should contain(%("occurrences"))
  end

  it "serializes to XML" do
    method = CycloneDX::EvidenceMethod.new(technique: "manifest-analysis", confidence: 1.0)
    occurrence = CycloneDX::EvidenceOccurrence.new(location: "package.json")
    identity = CycloneDX::EvidenceIdentity.new(
      field: "purl",
      confidence: 1.0,
      methods: [method],
      occurrences: [occurrence],
    )

    xml_str = XML.build(indent: "  ") do |xml|
      identity.to_xml(xml)
    end
    xml_str.should contain("<identity>")
    xml_str.should contain("<field>purl</field>")
    xml_str.should contain("<confidence>1.0</confidence>")
    xml_str.should contain("<methods>")
    xml_str.should contain("<technique>manifest-analysis</technique>")
    xml_str.should contain("<occurrences>")
    xml_str.should contain("<location>package.json</location>")
  end
end

describe CycloneDX::EvidenceCopyright do
  it "serializes to JSON and XML" do
    cr = CycloneDX::EvidenceCopyright.new(text: "Copyright 2024 Example Corp")
    json = cr.to_json
    json.should contain(%("text":"Copyright 2024 Example Corp"))

    xml_str = XML.build(indent: "  ") do |xml|
      cr.to_xml(xml)
    end
    xml_str.should contain("<copyright>")
    xml_str.should contain("<text>Copyright 2024 Example Corp</text>")
  end
end

describe CycloneDX::Evidence do
  it "serializes to JSON" do
    identity = CycloneDX::EvidenceIdentity.new(field: "name", confidence: 0.9)
    cr = CycloneDX::EvidenceCopyright.new(text: "Copyright 2024")
    evidence = CycloneDX::Evidence.new(identity: [identity], copyright: [cr])

    json = evidence.to_json
    json.should contain(%("identity"))
    json.should contain(%("copyright"))
  end

  it "serializes to XML" do
    identity = CycloneDX::EvidenceIdentity.new(field: "name")
    license = CycloneDX::License.new(id: "MIT")
    licenses = [license] of CycloneDX::License | CycloneDX::LicenseExpression
    evidence = CycloneDX::Evidence.new(identity: [identity], licenses: licenses)

    xml_str = XML.build(indent: "  ") do |xml|
      evidence.to_xml(xml)
    end
    xml_str.should contain("<evidence>")
    xml_str.should contain("<identity>")
    xml_str.should contain("<field>name</field>")
    xml_str.should contain("<licenses>")
    xml_str.should contain("<id>MIT</id>")
  end
end
