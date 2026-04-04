require "spec"
require "../../src/cyclonedx/bom"
require "../../src/cyclonedx/vulnerability"
require "../../src/cyclonedx/service"
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
end
