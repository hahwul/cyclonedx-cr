require "spec"
require "../../src/cyclonedx/composition"

describe CycloneDX::Composition do
  describe "#initialize" do
    it "initializes with aggregate only" do
      comp = CycloneDX::Composition.new(aggregate: "complete")
      comp.aggregate.should eq("complete")
      comp.assemblies.should be_nil
      comp.dependencies.should be_nil
      comp.vulnerabilities.should be_nil
    end

    it "initializes with all fields" do
      comp = CycloneDX::Composition.new(
        aggregate: "incomplete_first_party_opensource_only",
        bom_ref: "comp-1",
        assemblies: ["comp-a", "comp-b"],
        dependencies: ["dep-a"],
        vulnerabilities: ["vuln-a"],
      )
      comp.bom_ref.should eq("comp-1")
      comp.assemblies.should eq(["comp-a", "comp-b"])
      comp.dependencies.should eq(["dep-a"])
      comp.vulnerabilities.should eq(["vuln-a"])
    end
  end

  describe "#to_json" do
    it "serializes correctly" do
      comp = CycloneDX::Composition.new(
        aggregate: "incomplete",
        bom_ref: "comp-1",
        assemblies: ["lib-a@1.0.0"],
      )
      json = comp.to_json
      json.should contain(%("bom-ref":"comp-1"))
      json.should contain(%("aggregate":"incomplete"))
      json.should contain(%("assemblies"))
      json.should contain(%("lib-a@1.0.0"))
    end
  end

  describe "#to_xml" do
    it "serializes correctly" do
      comp = CycloneDX::Composition.new(
        aggregate: "incomplete_first_party_opensource_only",
        bom_ref: "comp-1",
        assemblies: ["lib-a@1.0.0", "lib-b@2.0.0"],
        dependencies: ["dep-ref"],
      )

      xml_str = XML.build(indent: "  ") do |xml|
        comp.to_xml(xml)
      end

      xml_str.should contain(%(<composition bom-ref="comp-1">))
      xml_str.should contain(%(<aggregate>incomplete_first_party_opensource_only</aggregate>))
      xml_str.should contain(%(<assemblies>))
      xml_str.should contain(%(<assembly ref="lib-a@1.0.0"/>))
      xml_str.should contain(%(<assembly ref="lib-b@2.0.0"/>))
      xml_str.should contain(%(<dependencies>))
      xml_str.should contain(%(<dependency ref="dep-ref"/>))
    end

    it "handles minimal composition" do
      comp = CycloneDX::Composition.new(aggregate: "unknown")

      xml_str = XML.build(indent: "  ") do |xml|
        comp.to_xml(xml)
      end

      xml_str.should contain(%(<composition>))
      xml_str.should contain(%(<aggregate>unknown</aggregate>))
      xml_str.should_not contain(%(<assemblies>))
      xml_str.should_not contain(%(<dependencies>))
    end
  end
end
