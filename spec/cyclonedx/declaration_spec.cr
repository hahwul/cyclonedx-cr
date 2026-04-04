require "spec"
require "../../src/cyclonedx/declaration"

describe CycloneDX::StandardRequirement do
  it "serializes to XML" do
    req = CycloneDX::StandardRequirement.new(
      bom_ref: "req-1",
      identifier: "PO.1.1",
      title: "Define security requirements",
      text: "All software shall have security requirements defined.",
    )
    xml_str = XML.build(indent: "  ") do |xml|
      req.to_xml(xml)
    end
    xml_str.should contain(%(<requirement bom-ref="req-1">))
    xml_str.should contain("<identifier>PO.1.1</identifier>")
    xml_str.should contain("<title>Define security requirements</title>")
  end
end

describe CycloneDX::Standard do
  it "serializes to JSON" do
    req = CycloneDX::StandardRequirement.new(identifier: "PO.1.1", title: "Sec reqs")
    standard = CycloneDX::Standard.new(
      bom_ref: "std-1",
      name: "NIST SSDF",
      version: "1.1",
      owner: "NIST",
      requirements: [req],
    )
    json = standard.to_json
    json.should contain(%("name":"NIST SSDF"))
    json.should contain(%("version":"1.1"))
    json.should contain(%("requirements"))
  end

  it "serializes to XML" do
    standard = CycloneDX::Standard.new(name: "OWASP ASVS", version: "4.0", owner: "OWASP")
    xml_str = XML.build(indent: "  ") do |xml|
      standard.to_xml(xml)
    end
    xml_str.should contain("<standard>")
    xml_str.should contain("<name>OWASP ASVS</name>")
    xml_str.should contain("<version>4.0</version>")
    xml_str.should contain("<owner>OWASP</owner>")
  end
end

describe CycloneDX::Claim do
  it "serializes to JSON and XML" do
    claim = CycloneDX::Claim.new(
      bom_ref: "claim-1",
      target: "comp-a@1.0.0",
      predicate: "Meets SSDF PO.1.1",
      reasoning: "Security requirements documented in JIRA",
      evidence: ["evidence-1"],
    )
    json = claim.to_json
    json.should contain(%("target":"comp-a@1.0.0"))
    json.should contain(%("predicate":"Meets SSDF PO.1.1"))

    xml_str = XML.build(indent: "  ") do |xml|
      claim.to_xml(xml)
    end
    xml_str.should contain(%(<claim bom-ref="claim-1">))
    xml_str.should contain("<target>comp-a@1.0.0</target>")
    xml_str.should contain("<reasoning>Security requirements documented in JIRA</reasoning>")
    xml_str.should contain("<ref>evidence-1</ref>")
  end
end

describe CycloneDX::Declarations do
  it "serializes to XML" do
    standard = CycloneDX::Standard.new(name: "NIST SSDF", version: "1.1")
    claim = CycloneDX::Claim.new(target: "app@1.0", predicate: "Compliant")
    decl = CycloneDX::Declarations.new(standards: [standard], claims: [claim])

    xml_str = XML.build(indent: "  ") do |xml|
      decl.to_xml(xml)
    end
    xml_str.should contain("<declarations>")
    xml_str.should contain("<standards>")
    xml_str.should contain("<name>NIST SSDF</name>")
    xml_str.should contain("<claims>")
    xml_str.should contain("<predicate>Compliant</predicate>")
  end
end
