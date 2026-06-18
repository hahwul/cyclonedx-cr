require "spec"
require "../../src/cyclonedx/evidence"

describe CycloneDX::EvidenceIdentity do
  it "serializes to JSON" do
    method = CycloneDX::EvidenceMethod.new(technique: "binary-analysis", confidence: 0.85)
    identity = CycloneDX::EvidenceIdentity.new(
      field: "name",
      confidence: 0.95,
      methods: [method],
    )
    json = identity.to_json
    json.should contain(%("field":"name"))
    json.should contain(%("confidence"))
    json.should contain(%("methods"))
    json.should contain(%("binary-analysis"))
  end

  it "serializes to XML" do
    method = CycloneDX::EvidenceMethod.new(technique: "manifest-analysis", confidence: 1.0)
    identity = CycloneDX::EvidenceIdentity.new(
      field: "purl",
      confidence: 1.0,
      methods: [method],
    )

    xml_str = XML.build(indent: "  ") do |xml|
      identity.to_xml(xml)
    end
    xml_str.should contain("<identity>")
    xml_str.should contain("<field>purl</field>")
    xml_str.should contain("<confidence>1.0</confidence>")
    xml_str.should contain("<methods>")
    xml_str.should contain("<technique>manifest-analysis</technique>")
    # occurrences are a componentEvidence-level field, not part of <identity>.
    xml_str.should_not contain("<occurrences>")
  end
end

describe CycloneDX::EvidenceCopyright do
  it "serializes to JSON and to a <text> element (wrapped by Evidence in <copyright>)" do
    cr = CycloneDX::EvidenceCopyright.new(text: "Copyright 2024 Example Corp")
    json = cr.to_json
    json.should contain(%("text":"Copyright 2024 Example Corp"))

    xml_str = XML.build(indent: "  ") do |xml|
      cr.to_xml(xml)
    end
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

  it "serializes occurrences (at the evidence level) and one <copyright> wrapper to XML" do
    identity = CycloneDX::EvidenceIdentity.new(field: "name")
    occurrence = CycloneDX::EvidenceOccurrence.new(location: "package.json")
    license = CycloneDX::License.new(id: "MIT")
    licenses = [license] of CycloneDX::License | CycloneDX::LicenseExpression
    evidence = CycloneDX::Evidence.new(
      identity: [identity], occurrences: [occurrence], licenses: licenses,
      copyright: [CycloneDX::EvidenceCopyright.new(text: "c1"), CycloneDX::EvidenceCopyright.new(text: "c2")])

    xml_str = XML.build(indent: "  ") do |xml|
      evidence.to_xml(xml)
    end
    xml_str.should contain("<evidence>")
    xml_str.should contain("<identity>")
    xml_str.should contain("<field>name</field>")
    xml_str.should contain("<occurrences>")
    xml_str.should contain("<location>package.json</location>")
    xml_str.should contain("<licenses>")
    xml_str.should contain("<id>MIT</id>")
    # A single <copyright> wrapper holding multiple <text> entries.
    xml_str.scan(/<copyright>/).size.should eq(1)
    xml_str.should contain("<text>c1</text>")
    xml_str.should contain("<text>c2</text>")
  end
end
