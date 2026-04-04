require "spec"
require "../../src/cyclonedx/annotation"

describe CycloneDX::Annotator do
  it "serializes to JSON" do
    org = CycloneDX::OrganizationalEntity.new(name: "Security Team")
    annotator = CycloneDX::Annotator.new(organization: org)
    json = annotator.to_json
    json.should contain(%("organization"))
    json.should contain(%("Security Team"))
  end

  it "serializes to XML" do
    ind = CycloneDX::OrganizationalContact.new(name: "John", email: "john@example.com")
    annotator = CycloneDX::Annotator.new(individual: ind)
    xml_str = XML.build(indent: "  ") do |xml|
      annotator.to_xml(xml)
    end
    xml_str.should contain("<annotator>")
    xml_str.should contain("<individual>")
    xml_str.should contain("<name>John</name>")
  end
end

describe CycloneDX::Annotation do
  it "serializes to JSON" do
    org = CycloneDX::OrganizationalEntity.new(name: "Review Team")
    annotator = CycloneDX::Annotator.new(organization: org)
    ann = CycloneDX::Annotation.new(
      bom_ref: "ann-1",
      subjects: ["comp-a@1.0.0", "comp-b@2.0.0"],
      annotator: annotator,
      timestamp: "2024-06-01T00:00:00Z",
      text: "Reviewed and approved",
    )
    json = ann.to_json
    json.should contain(%("bom-ref":"ann-1"))
    json.should contain(%("subjects"))
    json.should contain(%("comp-a@1.0.0"))
    json.should contain(%("timestamp":"2024-06-01T00:00:00Z"))
    json.should contain(%("text":"Reviewed and approved"))
  end

  it "serializes to XML" do
    ann = CycloneDX::Annotation.new(
      bom_ref: "ann-1",
      subjects: ["comp-a@1.0.0"],
      timestamp: "2024-06-01T00:00:00Z",
      text: "Audit note",
    )
    xml_str = XML.build(indent: "  ") do |xml|
      ann.to_xml(xml)
    end
    xml_str.should contain(%(<annotation bom-ref="ann-1">))
    xml_str.should contain("<subjects>")
    xml_str.should contain("<ref>comp-a@1.0.0</ref>")
    xml_str.should contain("<timestamp>2024-06-01T00:00:00Z</timestamp>")
    xml_str.should contain("<text>Audit note</text>")
  end
end
