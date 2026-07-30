require "spec"
# `src/main.cr` is the executable entrypoint: it calls `App.new.run` at the top
# level. Requiring it from a spec runs the whole CLI as a load-time side effect,
# which prints an SBOM into the spec output and — when `shard.lock` is absent —
# calls `exit(1)`, aborting the entire suite before any example runs. These
# examples only need the `App` class, so require that directly.
require "../src/app"

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

    it "supports spec version 1.7" do
      components = [CycloneDX::Component.new("test", "1.0.2")]
      bom = CycloneDX::BOM.new(components: components, spec_version: "1.7")
      json = bom.to_json
      json.should contain(%("specVersion":"1.7"))
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

    it "emits an XML namespace matching the declared version, and never a newer one" do
      CycloneDX::BOM::SUPPORTED_VERSIONS.each do |version|
        components = [CycloneDX::Component.new("test", "1.0.2")]
        bom = CycloneDX::BOM.new(components: components, spec_version: version)
        xml = bom.to_xml
        xml.should contain(%(xmlns="http://cyclonedx.org/schema/bom/#{version}"))
        (CycloneDX::BOM::SUPPORTED_VERSIONS - [version]).each do |other|
          xml.should_not contain("/bom/#{other}")
        end
      end
    end

    it "emits a $schema pointing at the declared version's JSON schema" do
      CycloneDX::BOM::SUPPORTED_VERSIONS.each do |version|
        components = [CycloneDX::Component.new("test", "1.0.2")]
        bom = CycloneDX::BOM.new(components: components, spec_version: version)
        bom.to_json.should contain(
          %("$schema":"http://cyclonedx.org/schema/bom-#{version}.schema.json"))
      end
    end
  end
end
