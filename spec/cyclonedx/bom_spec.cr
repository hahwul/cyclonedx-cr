require "spec"
require "../../src/cyclonedx/bom"
require "../../src/cyclonedx/vulnerability"
require "../../src/cyclonedx/service"
require "../../src/cyclonedx/composition"
require "../../src/cyclonedx/annotation"
require "../../src/cyclonedx/formulation"
require "../../src/cyclonedx/declaration"
require "uuid"

describe CycloneDX::BOM do
  describe "serialNumber consistency" do
    it "has a consistent serial number across XML generations" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.4")

      xml1 = bom.to_xml
      xml2 = bom.to_xml

      match1 = xml1.match(/serialNumber="([^"]+)"/)
      match2 = xml2.match(/serialNumber="([^"]+)"/)

      match1.should_not be_nil
      match2.should_not be_nil

      if match1 && match2
        match1[1].should eq(match2[1])
        match1[1].should start_with("urn:uuid:")
      end
    end

    it "includes serialNumber in JSON output matching the object state" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.4")

      xml = bom.to_xml
      match_xml = xml.match(/serialNumber="([^"]+)"/)
      match_xml.should_not be_nil

      json = bom.to_json
      json.should contain("serialNumber")

      if match_xml
        json.should contain(match_xml[1])
      end
    end
  end

  describe "dependencies" do
    it "includes dependencies in JSON output" do
      components = [CycloneDX::Component.new(name: "lib-a", version: "1.0.0", bom_ref: "lib-a@1.0.0")]
      deps = [
        CycloneDX::Dependency.new(ref: "my-app@1.0.0", depends_on: ["lib-a@1.0.0"]),
        CycloneDX::Dependency.new(ref: "lib-a@1.0.0"),
      ]
      bom = CycloneDX::BOM.new(components, "1.6", dependencies: deps)

      json = bom.to_json
      json.should contain(%("dependencies"))
      json.should contain(%("ref":"my-app@1.0.0"))
      json.should contain(%("dependsOn"))
      json.should contain(%("lib-a@1.0.0"))
    end

    it "includes dependencies in XML output" do
      components = [CycloneDX::Component.new(name: "lib-a", version: "1.0.0", bom_ref: "lib-a@1.0.0")]
      deps = [
        CycloneDX::Dependency.new(ref: "my-app@1.0.0", depends_on: ["lib-a@1.0.0"]),
        CycloneDX::Dependency.new(ref: "lib-a@1.0.0"),
      ]
      bom = CycloneDX::BOM.new(components, "1.6", dependencies: deps)

      xml = bom.to_xml
      xml.should contain("<dependencies>")
      xml.should contain(%(<dependency ref="my-app@1.0.0">))
      xml.should contain(%(<dependency ref="lib-a@1.0.0"/>))
    end

    it "omits dependencies element when nil" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.6")

      xml = bom.to_xml
      xml.should_not contain("<dependencies>")
    end
  end

  describe "properties" do
    it "includes properties in JSON output" do
      components = [] of CycloneDX::Component
      props = [
        CycloneDX::Property.new(name: "cdx:tool:name", value: "cyclonedx-cr"),
        CycloneDX::Property.new(name: "cdx:tool:version", value: "1.2.0"),
      ]
      bom = CycloneDX::BOM.new(components, "1.6", properties: props)

      json = bom.to_json
      json.should contain(%("properties"))
      json.should contain(%("name":"cdx:tool:name"))
      json.should contain(%("value":"cyclonedx-cr"))
    end

    it "includes properties in XML output" do
      components = [] of CycloneDX::Component
      props = [CycloneDX::Property.new(name: "cdx:tool:name", value: "cyclonedx-cr")]
      bom = CycloneDX::BOM.new(components, "1.6", properties: props)

      xml = bom.to_xml
      xml.should contain("<properties>")
      xml.should contain(%(<property name="cdx:tool:name">cyclonedx-cr</property>))
    end

    it "omits properties element when nil" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.6")

      xml = bom.to_xml
      xml.should_not contain("<properties>")
    end
  end

  describe "services" do
    it "includes services in JSON output" do
      components = [] of CycloneDX::Component
      svc = CycloneDX::Service.new(name: "auth-api", version: "1.0.0",
        endpoints: ["https://auth.example.com"])
      bom = CycloneDX::BOM.new(components, "1.6", services: [svc])

      json = bom.to_json
      json.should contain(%("services"))
      json.should contain(%("auth-api"))
      json.should contain(%("https://auth.example.com"))
    end

    it "includes services in XML output" do
      components = [] of CycloneDX::Component
      svc = CycloneDX::Service.new(name: "auth-api")
      bom = CycloneDX::BOM.new(components, "1.6", services: [svc])

      xml = bom.to_xml
      xml.should contain("<services>")
      xml.should contain("<name>auth-api</name>")
    end

    it "omits services element when nil" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.6")

      xml = bom.to_xml
      xml.should_not contain("<services>")
    end
  end

  describe "vulnerabilities" do
    it "includes vulnerabilities in JSON output" do
      components = [CycloneDX::Component.new(name: "lib-a", version: "1.0.0", bom_ref: "lib-a@1.0.0")]
      vuln = CycloneDX::Vulnerability.new(
        id: "CVE-2024-1234",
        source: CycloneDX::VulnerabilitySource.new(name: "NVD"),
        ratings: [CycloneDX::VulnerabilityRating.new(score: 9.8, severity: "critical")],
        affects: [CycloneDX::VulnerabilityAffect.new(ref: "lib-a@1.0.0")],
      )
      bom = CycloneDX::BOM.new(components, "1.6", vulnerabilities: [vuln])

      json = bom.to_json
      json.should contain(%("vulnerabilities"))
      json.should contain(%("CVE-2024-1234"))
      json.should contain(%("NVD"))
    end

    it "includes vulnerabilities in XML output" do
      components = [] of CycloneDX::Component
      vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1234")
      bom = CycloneDX::BOM.new(components, "1.6", vulnerabilities: [vuln])

      xml = bom.to_xml
      xml.should contain("<vulnerabilities>")
      xml.should contain("<id>CVE-2024-1234</id>")
    end

    it "omits vulnerabilities element when nil" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.6")

      xml = bom.to_xml
      xml.should_not contain("<vulnerabilities>")
    end
  end

  describe "compositions" do
    it "includes compositions in JSON output" do
      components = [] of CycloneDX::Component
      comp = CycloneDX::Composition.new(
        aggregate: "incomplete_first_party_opensource_only",
        assemblies: ["lib-a@1.0.0"],
      )
      bom = CycloneDX::BOM.new(components, "1.6", compositions: [comp])

      json = bom.to_json
      json.should contain(%("compositions"))
      json.should contain(%("incomplete_first_party_opensource_only"))
    end

    it "includes compositions in XML output" do
      components = [] of CycloneDX::Component
      comp = CycloneDX::Composition.new(aggregate: "complete")
      bom = CycloneDX::BOM.new(components, "1.6", compositions: [comp])

      xml = bom.to_xml
      xml.should contain("<compositions>")
      xml.should contain("<aggregate>complete</aggregate>")
    end

    it "omits compositions element when nil" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.6")

      xml = bom.to_xml
      xml.should_not contain("<compositions>")
    end
  end

  describe "annotations" do
    it "includes annotations in JSON output" do
      ann = CycloneDX::Annotation.new(
        subjects: ["comp-a@1.0.0"],
        text: "Reviewed",
        timestamp: "2024-01-01T00:00:00Z",
      )
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", annotations: [ann])

      json = bom.to_json
      json.should contain(%("annotations"))
      json.should contain(%("Reviewed"))
    end

    it "includes annotations in XML output" do
      ann = CycloneDX::Annotation.new(text: "Note")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", annotations: [ann])

      xml = bom.to_xml
      xml.should contain("<annotations>")
      xml.should contain("<text>Note</text>")
    end

    it "omits annotations when nil" do
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6")
      bom.to_xml.should_not contain("<annotations>")
    end
  end

  describe "formulation" do
    it "includes formulation in JSON output" do
      task = CycloneDX::Task.new(name: "build", task_types: ["build"])
      wf = CycloneDX::Workflow.new(uid: "wf-1", tasks: [task])
      formula = CycloneDX::Formula.new(workflows: [wf])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", formulation: [formula])

      json = bom.to_json
      json.should contain(%("formulation"))
      json.should contain(%("wf-1"))
    end

    it "includes formulation in XML output" do
      wf = CycloneDX::Workflow.new(uid: "wf-1", name: "CI")
      formula = CycloneDX::Formula.new(workflows: [wf])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", formulation: [formula])

      xml = bom.to_xml
      xml.should contain("<formulation>")
      xml.should contain("<uid>wf-1</uid>")
    end

    it "omits formulation when nil" do
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6")
      bom.to_xml.should_not contain("<formulation>")
    end
  end

  describe "declarations" do
    it "includes declarations in JSON output" do
      standard = CycloneDX::Standard.new(name: "NIST SSDF", version: "1.1")
      decl = CycloneDX::Declarations.new(standards: [standard])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", declarations: decl)

      json = bom.to_json
      json.should contain(%("declarations"))
      json.should contain(%("NIST SSDF"))
    end

    it "includes declarations in XML output" do
      claim = CycloneDX::Claim.new(predicate: "Compliant")
      decl = CycloneDX::Declarations.new(claims: [claim])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", declarations: decl)

      xml = bom.to_xml
      xml.should contain("<declarations>")
      xml.should contain("<predicate>Compliant</predicate>")
    end

    it "omits declarations when nil" do
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6")
      bom.to_xml.should_not contain("<declarations>")
    end
  end

  describe "externalReferences" do
    it "includes externalReferences in JSON output" do
      ext_ref = CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", external_references: [ext_ref])

      json = bom.to_json
      json.should contain(%("externalReferences"))
      json.should contain(%("website"))
      json.should contain(%("https://example.com"))
    end

    it "includes externalReferences in XML output" do
      ext_ref = CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/example/repo")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", external_references: [ext_ref])

      xml = bom.to_xml
      xml.should contain("<externalReferences>")
      xml.should contain(%(<reference type="vcs">))
      xml.should contain(%(<url>https://github.com/example/repo</url>))
    end

    it "omits externalReferences when nil" do
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6")
      bom.to_xml.should_not contain("<externalReferences>")
    end
  end

  describe "definitions" do
    it "includes definitions in JSON output" do
      req = CycloneDX::DefinitionRequirement.new(identifier: "REQ-1", title: "Requirement 1")
      standard = CycloneDX::DefinitionStandard.new(name: "NIST SSDF", version: "1.1", requirements: [req])
      defs = CycloneDX::Definitions.new(standards: [standard])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", definitions: defs)

      json = bom.to_json
      json.should contain(%("definitions"))
      json.should contain(%("NIST SSDF"))
      json.should contain(%("REQ-1"))
    end

    it "includes definitions in XML output" do
      standard = CycloneDX::DefinitionStandard.new(name: "ISO 27001", version: "2022")
      defs = CycloneDX::Definitions.new(standards: [standard])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", definitions: defs)

      xml = bom.to_xml
      xml.should contain("<definitions>")
      xml.should contain("<standards>")
      xml.should contain("<name>ISO 27001</name>")
    end

    it "omits definitions when nil" do
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6")
      bom.to_xml.should_not contain("<definitions>")
    end
  end
end
