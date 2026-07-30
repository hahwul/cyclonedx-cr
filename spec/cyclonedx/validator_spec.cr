require "spec"
require "../../src/cyclonedx/validator"
require "../../src/cyclonedx/formulation"

describe CycloneDX::Validator do
  describe "#validate" do
    it "passes a valid BOM" do
      comp = CycloneDX::Component.new(name: "lib", version: "1.0.0")
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
      validator.errors.should be_empty
    end

    it "detects invalid component type" do
      comp = CycloneDX::Component.new(name: "lib", version: "1.0.0", component_type: "invalid-type")
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.size.should eq(1)
      validator.errors[0].path.should eq("$.components[0].type")
      validator.errors[0].message.should contain("invalid type")
    end

    it "detects empty component name" do
      comp = CycloneDX::Component.new(name: "", version: "1.0.0")
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path == "$.components[0].name" }.should be_true
    end

    it "detects invalid vulnerability analysis state" do
      analysis = CycloneDX::VulnerabilityAnalysis.new(state: "bad_state")
      vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1", analysis: analysis)
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", vulnerabilities: [vuln])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.path.includes?("analysis.state")).should be_true
    end

    it "detects invalid rating score" do
      rating = CycloneDX::VulnerabilityRating.new(score: 15.0)
      vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1", ratings: [rating])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", vulnerabilities: [vuln])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.path.includes?("score")).should be_true
    end

    it "detects invalid composition aggregate" do
      comp = CycloneDX::Composition.new(aggregate: "totally_made_up")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", compositions: [comp])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.path.includes?("aggregate")).should be_true
    end

    it "detects invalid lifecycle phase" do
      lc = CycloneDX::Lifecycle.new(phase: "bad-phase")
      metadata = CycloneDX::Metadata.new(lifecycles: [lc])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", metadata: metadata)
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.path.includes?("phase")).should be_true
    end

    it "validates nested sub-components" do
      sub = CycloneDX::Component.new(name: "sub", version: "1.0", component_type: "bad")
      parent = CycloneDX::Component.new(name: "parent", version: "1.0", components: [sub])
      bom = CycloneDX::BOM.new([parent], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.path.includes?("components[0]")).should be_true
    end

    it "validates the root component in metadata.component" do
      # The root component lives in metadata.component; an invalid type there
      # is schema-invalid and must be flagged just like a bom.components entry.
      root = CycloneDX::Component.new(name: "root", version: "1.0", component_type: "not-a-type")
      metadata = CycloneDX::Metadata.new(component: root)
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", metadata: metadata)
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path == "$.metadata.component.type" }.should be_true
    end

    it "passes a valid root component in metadata.component" do
      root = CycloneDX::Component.new(name: "root", version: "1.0", component_type: "application")
      metadata = CycloneDX::Metadata.new(component: root)
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", metadata: metadata)
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
      validator.errors.should be_empty
    end

    it "reports multiple errors" do
      comp = CycloneDX::Component.new(name: "", version: "", component_type: "bad")
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.size.should be >= 3
    end

    it "detects invalid task type in formulation" do
      task = CycloneDX::Task.new(name: "bad", task_types: ["build", "invalid_type"])
      wf = CycloneDX::Workflow.new(uid: "wf-1", tasks: [task])
      formula = CycloneDX::Formula.new(workflows: [wf])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", formulation: [formula])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("taskTypes") && e.message.includes?("invalid_type") }.should be_true
    end

    it "passes valid task types" do
      task = CycloneDX::Task.new(name: "ci", task_types: ["build", "test", "deploy"])
      wf = CycloneDX::Workflow.new(uid: "wf-1", tasks: [task])
      formula = CycloneDX::Formula.new(workflows: [wf])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", formulation: [formula])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
    end

    it "validates nested sub-services" do
      sub = CycloneDX::Service.new(name: "")
      parent = CycloneDX::Service.new(name: "parent", services: [sub])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", services: [parent])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path == "$.services[0].services[0].name" }.should be_true
    end

    it "detects invalid affected version status" do
      ver = CycloneDX::AffectedVersion.new(version: "1.0.0", status: "bad_status")
      affect = CycloneDX::VulnerabilityAffect.new(ref: "lib@1.0.0", versions: [ver])
      vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1", affects: [affect])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", vulnerabilities: [vuln])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("versions[0].status") && e.message.includes?("bad_status") }.should be_true
    end

    it "passes valid affected version status" do
      ver = CycloneDX::AffectedVersion.new(version: "1.0.0", status: "affected")
      affect = CycloneDX::VulnerabilityAffect.new(ref: "lib@1.0.0", versions: [ver])
      vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1", affects: [affect])
      # `affects[].ref` has to resolve to something in this BOM, so the affected
      # component has to actually be present.
      affected = CycloneDX::Component.new(name: "lib", version: "1.0.0", bom_ref: "lib@1.0.0")
      bom = CycloneDX::BOM.new([affected], "1.6", vulnerabilities: [vuln])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
      validator.errors.should be_empty
    end

    it "detects a duplicate bom-ref anywhere in the document" do
      bom = CycloneDX::BOM.new([
        CycloneDX::Component.new(name: "a", version: "1", bom_ref: "dup"),
        CycloneDX::Component.new(name: "b", version: "1", bom_ref: "dup"),
      ], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.message.includes?("duplicate bom-ref 'dup'")).should be_true
    end

    it "detects a duplicate bom-ref across different kinds of object" do
      comp = CycloneDX::Component.new(name: "a", version: "1", bom_ref: "shared")
      svc = CycloneDX::Service.new(name: "svc", bom_ref: "shared")
      bom = CycloneDX::BOM.new([comp], "1.6", services: [svc])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.message.includes?("duplicate bom-ref 'shared'")).should be_true
    end

    it "detects dangling dependency graph references" do
      bom = CycloneDX::BOM.new(
        [CycloneDX::Component.new(name: "a", version: "1", bom_ref: "a@1")], "1.6",
        dependencies: [CycloneDX::Dependency.new(ref: "a@1", depends_on: ["ghost@9"])])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any?(&.message.includes?("unknown bom-ref 'ghost@9'")).should be_true
    end

    it "accepts a cross-BOM link as a reference" do
      bom = CycloneDX::BOM.new(
        [CycloneDX::Component.new(name: "a", version: "1", bom_ref: "a@1")], "1.6",
        dependencies: [CycloneDX::Dependency.new(ref: "a@1",
          depends_on: ["urn:cdx:f7b2c9de-0000-4000-8000-000000000000/1#other"])])
      CycloneDX::Validator.new.validate(bom).should be_true
    end

    it "detects a license with neither an id nor a name" do
      comp = CycloneDX::Component.new(name: "a", version: "1",
        licenses: [CycloneDX::License.new(url: "https://x.example")] of CycloneDX::License | CycloneDX::LicenseExpression)
      validator = CycloneDX::Validator.new
      validator.validate(CycloneDX::BOM.new([comp], "1.6")).should be_false
      validator.errors.any?(&.message.includes?("either an 'id' or a 'name'")).should be_true
    end

    it "detects a malformed metadata timestamp" do
      md = CycloneDX::Metadata.new(timestamp: "not-a-date")
      validator = CycloneDX::Validator.new
      validator.validate(CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", metadata: md)).should be_false
      validator.errors.any?(&.path.== "$.metadata.timestamp").should be_true
    end

    it "accepts an RFC 3339 metadata timestamp" do
      md = CycloneDX::Metadata.new(timestamp: "2024-01-01T00:00:00Z")
      CycloneDX::Validator.new
        .validate(CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", metadata: md)).should be_true
    end

    it "detects a malformed CPE and accepts well-formed ones" do
      bad = CycloneDX::Component.new(name: "a", version: "1", cpe: "nope")
      validator = CycloneDX::Validator.new
      validator.validate(CycloneDX::BOM.new([bad], "1.6")).should be_false
      validator.errors.any?(&.path.== "$.components[0].cpe").should be_true

      ["cpe:2.3:a:o:root:1.0.0:*:*:*:*:*:*:*", "cpe:/a:vendor:product:1.0"].each do |cpe|
        comp = CycloneDX::Component.new(name: "a", version: "1", cpe: cpe)
        CycloneDX::Validator.new.validate(CycloneDX::BOM.new([comp], "1.6")).should be_true
      end
    end

    it "detects an invalid component data type" do
      comp = CycloneDX::Component.new(name: "a", version: "1",
        data: [CycloneDX::ComponentData.new(data_type: "not-a-type", name: "d")])
      validator = CycloneDX::Validator.new
      validator.validate(CycloneDX::BOM.new([comp], "1.6")).should be_false
      validator.errors.any?(&.message.includes?("invalid data type 'not-a-type'")).should be_true
    end

    it "detects an invalid hash algorithm on a deserialized component" do
      # `from_json` bypasses the constructor guard, so the Validator must
      # still catch an out-of-enum algorithm.
      json = %q({
        "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
        "serialNumber":"urn:uuid:test",
        "components":[{
          "type":"library","name":"lib","version":"1.0",
          "hashes":[{"alg":"SHA-999","content":"deadbeef"}]
        }]
      })
      bom = CycloneDX::BOM.from_json(json)
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("hashes[0].alg") && e.message.includes?("SHA-999") }.should be_true
    end

    it "passes a valid hash algorithm" do
      hashes = [CycloneDX::Hash.new(algorithm: "SHA-512", content: "deadbeef")]
      comp = CycloneDX::Component.new(name: "lib", version: "1.0", hashes: hashes)
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
    end

    it "detects an invalid external reference type on a deserialized BOM" do
      json = %q({
        "bomFormat":"CycloneDX","specVersion":"1.6","version":1,
        "serialNumber":"urn:uuid:test",
        "components":[],
        "externalReferences":[{"type":"made-up","url":"https://example.com"}]
      })
      bom = CycloneDX::BOM.from_json(json)
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("externalReferences[0].type") && e.message.includes?("made-up") }.should be_true
    end

    it "passes a valid external reference type" do
      ref = CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")
      comp = CycloneDX::Component.new(name: "lib", version: "1.0", external_references: [ref])
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
    end

    it "formats error messages with to_s" do
      comp = CycloneDX::Component.new(name: "", version: "1.0")
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom)
      validator.errors[0].to_s.should contain("$.components[0]")
    end
  end
end
