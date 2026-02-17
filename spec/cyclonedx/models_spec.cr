require "spec"
require "../../src/cyclonedx/models"

describe CycloneDX::License do
  describe "#initialize" do
    it "can be initialized with an id" do
      license = CycloneDX::License.new(id: "MIT")
      license.id.should eq("MIT")
      license.name.should be_nil
    end

    it "can be initialized with a name" do
      license = CycloneDX::License.new(name: "My License")
      license.name.should eq("My License")
      license.id.should be_nil
    end

    it "can be initialized with both id and name" do
      license = CycloneDX::License.new(id: "MIT", name: "MIT License")
      license.id.should eq("MIT")
      license.name.should eq("MIT License")
    end

    it "can be initialized with no arguments" do
      license = CycloneDX::License.new
      license.id.should be_nil
      license.name.should be_nil
    end
  end

  describe "#to_json" do
    it "serializes to JSON correctly with id" do
      license = CycloneDX::License.new(id: "MIT")
      json = license.to_json
      json.should contain(%("id":"MIT"))
      json.should_not contain(%("name"))
    end

    it "serializes to JSON correctly with name" do
      license = CycloneDX::License.new(name: "My License")
      json = license.to_json
      json.should contain(%("name":"My License"))
      json.should_not contain(%("id"))
    end

    it "serializes to JSON correctly with both" do
      license = CycloneDX::License.new(id: "MIT", name: "MIT License")
      json = license.to_json
      json.should contain(%("id":"MIT"))
      json.should contain(%("name":"MIT License"))
    end
  end

  describe "#to_xml" do
    it "serializes to XML with id" do
      license = CycloneDX::License.new(id: "MIT")
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain("<license>")
      xml_str.should contain("<id>MIT</id>")
      xml_str.should_not contain("<name>")
    end

    it "serializes to XML with name" do
      license = CycloneDX::License.new(name: "My License")
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain("<license>")
      xml_str.should contain("<name>My License</name>")
      xml_str.should_not contain("<id>")
    end

    it "prefers id over name in XML serialization" do
      license = CycloneDX::License.new(id: "MIT", name: "MIT License")
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain("<id>MIT</id>")
      xml_str.should_not contain("<name>MIT License</name>")
    end

    it "generates empty license tag if neither id nor name is present" do
      license = CycloneDX::License.new
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain("<license/>")
      xml_str.should_not contain("<id>")
      xml_str.should_not contain("<name>")
    end
  end
end
