require "spec"
require "../../src/cyclonedx/component"

describe CycloneDX::Component do
  describe "#initialize" do
    it "initializes with required arguments" do
      component = CycloneDX::Component.new(name: "my-lib", version: "1.0.0")
      component.name.should eq "my-lib"
      component.version.should eq "1.0.0"
      component.component_type.should eq "library"
      component.purl.should be_nil
      component.description.should be_nil
      component.author.should be_nil
      component.licenses.should be_nil
      component.external_references.should be_nil
    end

    it "initializes with all arguments" do
      licenses = [CycloneDX::License.new(name: "MIT")]
      refs = [CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")]
      component = CycloneDX::Component.new(
        name: "my-app",
        version: "2.0.0",
        component_type: "application",
        purl: "pkg:gem/my-app@2.0.0",
        description: "A test app",
        author: "John Doe",
        licenses: licenses,
        external_references: refs
      )

      component.name.should eq "my-app"
      component.version.should eq "2.0.0"
      component.component_type.should eq "application"
      component.purl.should eq "pkg:gem/my-app@2.0.0"
      component.description.should eq "A test app"
      component.author.should eq "John Doe"
      component.licenses.should eq licenses
      component.external_references.should eq refs
    end
  end

  describe "#to_json" do
    it "serializes to JSON correctly" do
      licenses = [CycloneDX::License.new(name: "MIT")]
      refs = [CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")]
      component = CycloneDX::Component.new(
        name: "json-lib",
        version: "3.0.0",
        component_type: "library",
        purl: "pkg:npm/json-lib@3.0.0",
        description: "JSON lib",
        author: "Jane Doe",
        licenses: licenses,
        external_references: refs
      )

      json = component.to_json
      json.should contain %("type":"library")
      json.should contain %("name":"json-lib")
      json.should contain %("version":"3.0.0")
      json.should contain %("purl":"pkg:npm/json-lib@3.0.0")
      json.should contain %("description":"JSON lib")
      json.should contain %("author":"Jane Doe")
      json.should contain %("licenses")
      json.should contain %("MIT")
      json.should contain %("externalReferences")
      json.should contain %("website")
      json.should contain %("https://example.com")
    end
  end

  describe "#to_xml" do
    it "serializes to XML correctly" do
      licenses = [CycloneDX::License.new(name: "Apache-2.0")]
      refs = [CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/example/xml-lib")]
      component = CycloneDX::Component.new(
        name: "xml-lib",
        version: "4.0.0",
        component_type: "library",
        purl: "pkg:maven/xml-lib@4.0.0",
        description: "XML lib",
        author: "Xml Author",
        licenses: licenses,
        external_references: refs
      )

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<component type="library">)
      xml_content.should contain %(<name>xml-lib</name>)
      xml_content.should contain %(<version>4.0.0</version>)
      xml_content.should contain %(<purl>pkg:maven/xml-lib@4.0.0</purl>)
      xml_content.should contain %(<description>XML lib</description>)
      xml_content.should contain %(<author>Xml Author</author>)
      xml_content.should contain %(<licenses>)
      xml_content.should contain %(<license>)
      xml_content.should contain %(<name>Apache-2.0</name>)
      xml_content.should contain %(<externalReferences>)
      xml_content.should contain %(<reference type="vcs">)
      xml_content.should contain %(<url>https://github.com/example/xml-lib</url>)
    end

    it "handles optional fields being nil in XML" do
      component = CycloneDX::Component.new(name: "minimal", version: "0.1.0")

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<component type="library">)
      xml_content.should contain %(<name>minimal</name>)
      xml_content.should contain %(<version>0.1.0</version>)
      xml_content.should_not contain %(<purl>)
      xml_content.should_not contain %(<description>)
      xml_content.should_not contain %(<author>)
      xml_content.should_not contain %(<licenses>)
      xml_content.should_not contain %(<externalReferences>)
    end
  end
end
