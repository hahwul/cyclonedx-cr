require "spec"
require "../../src/cyclonedx/bom"
require "../../src/cyclonedx/vulnerability"
require "../../src/cyclonedx/service"
require "../../src/cyclonedx/composition"

describe "BOM JSON deserialization" do
  it "deserializes a minimal BOM" do
    json = %q({"bomFormat":"CycloneDX","specVersion":"1.6","version":1,"serialNumber":"urn:uuid:abc-123","components":[]})
    bom = CycloneDX::BOM.from_json(json)
    bom.bom_format.should eq("CycloneDX")
    bom.spec_version.should eq("1.6")
    bom.bom_version.should eq(1)
    bom.serial_number.should eq("urn:uuid:abc-123")
    bom.components.should be_empty
  end

  it "deserializes components" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[
        {"type":"library","name":"lib-a","version":"1.0.0","purl":"pkg:github/owner/lib-a@1.0.0","scope":"required"},
        {"type":"application","name":"app","version":"2.0.0","bom-ref":"app@2.0.0"}
      ]
    })
    bom = CycloneDX::BOM.from_json(json)
    bom.components.size.should eq(2)
    bom.components[0].name.should eq("lib-a")
    bom.components[0].component_type.should eq("library")
    bom.components[0].purl.should eq("pkg:github/owner/lib-a@1.0.0")
    bom.components[0].scope.should eq("required")
    bom.components[1].bom_ref.should eq("app@2.0.0")
  end

  it "deserializes metadata" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "metadata":{
        "timestamp":"2024-01-01T00:00:00Z",
        "tools":[{"vendor":"test","name":"tool","version":"1.0"}],
        "component":{"type":"application","name":"my-app","version":"1.0.0"}
      },
      "components":[]
    })
    bom = CycloneDX::BOM.from_json(json)
    bom.metadata.should_not be_nil
    md = bom.metadata.not_nil!
    md.timestamp.should eq("2024-01-01T00:00:00Z")
    md.tools.not_nil!.size.should eq(1)
    md.component.not_nil!.name.should eq("my-app")
  end

  it "deserializes dependencies" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[{"type":"library","name":"lib-a","version":"1.0.0","bom-ref":"lib-a@1.0.0"}],
      "dependencies":[
        {"ref":"app@1.0.0","dependsOn":["lib-a@1.0.0"]},
        {"ref":"lib-a@1.0.0","dependsOn":[]}
      ]
    })
    bom = CycloneDX::BOM.from_json(json)
    deps = bom.dependencies.not_nil!
    deps.size.should eq(2)
    deps[0].ref.should eq("app@1.0.0")
    deps[0].depends_on.not_nil!.should eq(["lib-a@1.0.0"])
  end

  it "deserializes properties" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[],
      "properties":[{"name":"cdx:tool","value":"test"}]
    })
    bom = CycloneDX::BOM.from_json(json)
    props = bom.properties.not_nil!
    props.size.should eq(1)
    props[0].name.should eq("cdx:tool")
    props[0].value.should eq("test")
  end

  it "deserializes vulnerabilities" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[],
      "vulnerabilities":[{
        "id":"CVE-2024-1234",
        "source":{"name":"NVD"},
        "ratings":[{"score":9.8,"severity":"critical"}],
        "cwes":[79],
        "analysis":{"state":"not_affected","justification":"code_not_reachable"}
      }]
    })
    bom = CycloneDX::BOM.from_json(json)
    vulns = bom.vulnerabilities.not_nil!
    vulns.size.should eq(1)
    vulns[0].id.should eq("CVE-2024-1234")
    vulns[0].source.not_nil!.name.should eq("NVD")
    vulns[0].ratings.not_nil![0].score.should eq(9.8)
    vulns[0].cwes.should eq([79])
    vulns[0].analysis.not_nil!.state.should eq("not_affected")
  end

  it "deserializes licenses (simple and expression)" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[{
        "type":"library","name":"lib","version":"1.0",
        "licenses":[{"id":"MIT","url":"https://opensource.org/licenses/MIT"}]
      }]
    })
    bom = CycloneDX::BOM.from_json(json)
    licenses = bom.components[0].licenses.not_nil!
    licenses.size.should eq(1)
  end

  it "ignores unknown fields gracefully (forward compatibility)" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[{"type":"library","name":"lib","version":"1.0","futureField":"ignored"}],
      "futureTopLevel":{"nested":"data"},
      "anotherUnknown":42
    })
    bom = CycloneDX::BOM.from_json(json)
    bom.components.size.should eq(1)
    bom.components[0].name.should eq("lib")
  end

  it "deserializes vulnerability with new fields" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[],
      "vulnerabilities":[{
        "id":"CVE-2024-1234",
        "workaround":"Disable feature X",
        "aliases":["GHSA-xxxx-yyyy"],
        "advisories":[{"title":"Advisory 1","url":"https://example.com/advisory"}],
        "rejected":"2024-06-01T00:00:00Z",
        "proofOfConcept":{"reproductionSteps":"Step 1","environment":"Linux"}
      }]
    })
    bom = CycloneDX::BOM.from_json(json)
    vuln = bom.vulnerabilities.not_nil![0]
    vuln.workaround.should eq("Disable feature X")
    vuln.aliases.should eq(["GHSA-xxxx-yyyy"])
    vuln.advisories.not_nil![0].title.should eq("Advisory 1")
    vuln.advisories.not_nil![0].url.should eq("https://example.com/advisory")
    vuln.rejected.should eq("2024-06-01T00:00:00Z")
    vuln.proof_of_concept.not_nil!.reproduction_steps.should eq("Step 1")
    vuln.proof_of_concept.not_nil!.environment.should eq("Linux")
  end

  it "deserializes BOM externalReferences" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[],
      "externalReferences":[{"type":"website","url":"https://example.com"}]
    })
    bom = CycloneDX::BOM.from_json(json)
    refs = bom.external_references.not_nil!
    refs.size.should eq(1)
    refs[0].ref_type.should eq("website")
    refs[0].url.should eq("https://example.com")
  end

  it "deserializes component releaseNotes" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[{
        "type":"library","name":"lib","version":"1.0.0",
        "releaseNotes":{"type":"major","title":"v1.0.0","description":"Initial release"}
      }]
    })
    bom = CycloneDX::BOM.from_json(json)
    rn = bom.components[0].release_notes.not_nil!
    rn.release_type.should eq("major")
    rn.title.should eq("v1.0.0")
    rn.description.should eq("Initial release")
  end

  it "deserializes BOM definitions" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[],
      "definitions":{
        "standards":[{
          "bom-ref":"std-1",
          "name":"NIST SSDF",
          "version":"1.1",
          "owner":"NIST",
          "requirements":[{"identifier":"PO.1","title":"Define Security Requirements"}]
        }]
      }
    })
    bom = CycloneDX::BOM.from_json(json)
    defs = bom.definitions.not_nil!
    std = defs.standards.not_nil![0]
    std.bom_ref.should eq("std-1")
    std.name.should eq("NIST SSDF")
    std.version.should eq("1.1")
    std.owner.should eq("NIST")
    req = std.requirements.not_nil![0]
    req.identifier.should eq("PO.1")
    req.title.should eq("Define Security Requirements")
  end

  it "deserializes component cryptoProperties" do
    json = %q({
      "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
      "serialNumber":"urn:uuid:test",
      "components":[{
        "type":"cryptographic-asset","name":"aes","version":"1.0.0",
        "cryptoProperties":{"assetType":"algorithm","oid":"2.16.840.1.101.3.4.1.6"}
      }]
    })
    bom = CycloneDX::BOM.from_json(json)
    crypto = bom.components[0].crypto_properties.not_nil!
    crypto.asset_type.should eq("algorithm")
    crypto.oid.should eq("2.16.840.1.101.3.4.1.6")
  end

  it "round-trips through JSON serialization" do
    components = [CycloneDX::Component.new(name: "lib", version: "1.0.0", bom_ref: "lib@1.0.0")]
    deps = [CycloneDX::Dependency.new(ref: "lib@1.0.0")]
    props = [CycloneDX::Property.new(name: "test", value: "val")]
    original = CycloneDX::BOM.new(components, "1.6", dependencies: deps, properties: props)

    json = original.to_json
    restored = CycloneDX::BOM.from_json(json)

    restored.spec_version.should eq(original.spec_version)
    restored.serial_number.should eq(original.serial_number)
    restored.components.size.should eq(1)
    restored.components[0].name.should eq("lib")
    restored.dependencies.not_nil!.size.should eq(1)
    restored.properties.not_nil!.size.should eq(1)
  end
end
