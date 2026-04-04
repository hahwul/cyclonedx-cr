require "spec"
require "json"
require "xml"
require "../../src/cyclonedx/metadata"
require "../../src/cyclonedx/component"
require "../../src/cyclonedx/models"

describe CycloneDX::Metadata do
  describe "#initialize" do
    it "can be initialized with no arguments" do
      metadata = CycloneDX::Metadata.new
      metadata.component.should be_nil
      metadata.tools.should be_nil
      metadata.authors.should be_nil
      metadata.timestamp.should be_nil
    end

    it "can be initialized with a component" do
      component = CycloneDX::Component.new(name: "test-component", version: "1.0.0")
      metadata = CycloneDX::Metadata.new(component: component)
      metadata.component.should eq(component)
    end

    it "can be initialized with tools" do
      tool = CycloneDX::Tool.new(vendor: "vendor", name: "tool", version: "1.0")
      metadata = CycloneDX::Metadata.new(tools: [tool])
      metadata.tools.should eq([tool])
    end

    it "can be initialized with authors" do
      author = CycloneDX::OrganizationalContact.new(name: "Author Name", email: "author@example.com")
      metadata = CycloneDX::Metadata.new(authors: [author])
      metadata.authors.should eq([author])
    end

    it "can be initialized with a timestamp" do
      metadata = CycloneDX::Metadata.new(timestamp: "2024-01-01T00:00:00Z")
      metadata.timestamp.should eq("2024-01-01T00:00:00Z")
    end

    it "can be initialized with properties" do
      props = [CycloneDX::Property.new(name: "cdx:tool:name", value: "test")]
      metadata = CycloneDX::Metadata.new(properties: props)
      metadata.properties.should eq(props)
    end

    it "can be initialized with lifecycles" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      metadata = CycloneDX::Metadata.new(lifecycles: [lc])
      metadata.lifecycles.not_nil!.size.should eq(1)
      metadata.lifecycles.not_nil![0].phase.should eq("build")
    end

    it "can be initialized with manufacture and supplier" do
      mfr = CycloneDX::OrganizationalEntity.new(name: "Manufacturer Inc")
      sup = CycloneDX::OrganizationalEntity.new(name: "Supplier Inc")
      metadata = CycloneDX::Metadata.new(manufacture: mfr, supplier: sup)
      metadata.manufacture.not_nil!.name.should eq("Manufacturer Inc")
      metadata.supplier.not_nil!.name.should eq("Supplier Inc")
    end
  end

  describe "#to_json" do
    it "serializes correctly to JSON" do
      component = CycloneDX::Component.new(name: "test-component", version: "1.0.0")
      tool = CycloneDX::Tool.new(vendor: "vendor", name: "tool", version: "1.0")
      author = CycloneDX::OrganizationalContact.new(name: "Author Name", email: "author@example.com")

      metadata = CycloneDX::Metadata.new(
        component: component,
        tools: [tool],
        authors: [author],
        timestamp: "2024-01-01T00:00:00Z"
      )

      json_string = metadata.to_json
      json = JSON.parse(json_string)

      json["component"]["name"].as_s.should eq("test-component")
      json["tools"][0]["vendor"].as_s.should eq("vendor")
      json["authors"][0]["name"].as_s.should eq("Author Name")
      json["timestamp"].as_s.should eq("2024-01-01T00:00:00Z")
    end
  end

  describe "#to_xml" do
    it "serializes correctly to XML" do
      component = CycloneDX::Component.new(name: "test-component", version: "1.0.0")
      tool = CycloneDX::Tool.new(vendor: "vendor", name: "tool", version: "1.0")
      author = CycloneDX::OrganizationalContact.new(name: "Author Name", email: "author@example.com")

      metadata = CycloneDX::Metadata.new(
        component: component,
        tools: [tool],
        authors: [author],
        timestamp: "2024-01-01T00:00:00Z"
      )

      io = IO::Memory.new
      xml = XML::Builder.new(io)
      metadata.to_xml(xml)
      xml.flush
      xml_string = io.to_s

      xml_string.should contain("<metadata>")
      xml_string.should contain("<timestamp>2024-01-01T00:00:00Z</timestamp>")
      xml_string.should contain("<tools>")
      xml_string.should contain("<tool>")
      xml_string.should contain("<vendor>vendor</vendor>")
      xml_string.should contain("<name>tool</name>")
      xml_string.should contain("<version>1.0</version>")

      xml_string.should contain("<authors>")
      xml_string.should contain("<author>")
      xml_string.should contain("<name>Author Name</name>")
      xml_string.should contain("<email>author@example.com</email>")

      xml_string.should contain("component type=\"library\"")
      xml_string.should contain("<name>test-component</name>")
      xml_string.should contain("<version>1.0.0</version>")

      xml_string.should contain("</metadata>")
    end

    it "serializes lifecycles, manufacture, and supplier to XML" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      mfr = CycloneDX::OrganizationalEntity.new(name: "Mfr Corp")
      sup = CycloneDX::OrganizationalEntity.new(name: "Sup Corp")
      metadata = CycloneDX::Metadata.new(lifecycles: [lc], manufacture: mfr, supplier: sup)

      io = IO::Memory.new
      xml = XML::Builder.new(io)
      metadata.to_xml(xml)
      xml.flush
      xml_string = io.to_s

      xml_string.should contain("<lifecycles>")
      xml_string.should contain("<lifecycle>")
      xml_string.should contain("<phase>build</phase>")
      xml_string.should contain("<manufacture>")
      xml_string.should contain("<name>Mfr Corp</name>")
      xml_string.should contain("<supplier>")
      xml_string.should contain("<name>Sup Corp</name>")
    end

    it "serializes properties to XML" do
      props = [CycloneDX::Property.new(name: "cdx:tool:name", value: "test")]
      metadata = CycloneDX::Metadata.new(properties: props)

      io = IO::Memory.new
      xml = XML::Builder.new(io)
      metadata.to_xml(xml)
      xml.flush
      xml_string = io.to_s

      xml_string.should contain("<properties>")
      xml_string.should contain(%(<property name="cdx:tool:name">test</property>))
    end
  end
end
