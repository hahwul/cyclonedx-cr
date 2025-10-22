require "spec"
require "../src/main"

describe App do
  it "runs without errors" do
    # This is a very basic test to ensure the app doesn't crash.
    # We'll need to add more specific tests later.
    app = App.new
    # We need to mock the file system to test this properly.
    # For now, we'll just check that the App class can be instantiated.
    app.should_not be_nil
  end
end

describe CycloneDX::BOM do
  describe "spec version support" do
    it "supports spec version 1.4" do
      components = [CycloneDX::Component.new("test", "1.0.0")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.4")
      json = bom.to_json
      json.should contain(%("specVersion":"1.4"))
    end

    it "supports spec version 1.5" do
      components = [CycloneDX::Component.new("test", "1.0.0")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.5")
      json = bom.to_json
      json.should contain(%("specVersion":"1.5"))
    end

    it "supports spec version 1.6" do
      components = [CycloneDX::Component.new("test", "1.0.0")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.6")
      json = bom.to_json
      json.should contain(%("specVersion":"1.6"))
    end

    it "supports spec version 1.7" do
      components = [CycloneDX::Component.new("test", "1.0.0")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.7")
      json = bom.to_json
      json.should contain(%("specVersion":"1.7"))
    end

    it "generates correct XML namespace for spec version 1.7" do
      components = [CycloneDX::Component.new("test", "1.0.0")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.7")
      xml = bom.to_xml
      xml.should contain(%(xmlns="http://cyclonedx.org/schema/bom/1.7"))
    end
  end
end
