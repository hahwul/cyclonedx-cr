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

  it "advertises a VERSION matching shard.yml" do
    shard_yml = File.read(File.expand_path("../shard.yml", __DIR__))
    if match = shard_yml.match(/^version:\s*(\S+)\s*$/m)
      App::VERSION.should eq(match[1])
    else
      fail "shard.yml has no version field"
    end
  end
end

describe CycloneDX::BOM do
  describe "spec version support" do
    it "supports spec version 1.4" do
      components = [CycloneDX::Component.new("test", "1.0.2")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.4")
      json = bom.to_json
      json.should contain(%("specVersion":"1.4"))
    end

    it "supports spec version 1.5" do
      components = [CycloneDX::Component.new("test", "1.0.2")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.5")
      json = bom.to_json
      json.should contain(%("specVersion":"1.5"))
    end

    it "supports spec version 1.6" do
      components = [CycloneDX::Component.new("test", "1.0.2")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.6")
      json = bom.to_json
      json.should contain(%("specVersion":"1.6"))
    end

    it "rejects the unsupported 1.7 spec version" do
      # 1.6 is the latest published CycloneDX spec; 1.7 does not exist.
      components = [CycloneDX::Component.new("test", "1.0.2")]
      expect_raises(ArgumentError, "Unsupported spec version") do
        CycloneDX::BOM.new(components: components, spec_version: "1.7")
      end
    end

    it "raises on unsupported spec version" do
      components = [CycloneDX::Component.new("test", "1.0.2")]
      expect_raises(ArgumentError, "Unsupported spec version") do
        CycloneDX::BOM.new(components: components, spec_version: "9.9")
      end
    end

    it "generates correct XML namespace for spec version 1.6" do
      components = [CycloneDX::Component.new("test", "1.0.2")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.6")
      xml = bom.to_xml
      xml.should contain(%(xmlns="http://cyclonedx.org/schema/bom/1.6"))
    end

    it "never emits a 1.7 XML namespace for any supported version" do
      CycloneDX::BOM::SUPPORTED_VERSIONS.each do |version|
        components = [CycloneDX::Component.new("test", "1.0.2")]
        bom = CycloneDX::BOM.new(components: components, spec_version: version)
        bom.to_xml.should_not contain("/bom/1.7")
      end
    end
  end
end
