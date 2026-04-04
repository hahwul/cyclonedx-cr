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
      validator.errors.any? { |e| e.path.includes?("analysis.state") }.should be_true
    end

    it "detects invalid rating score" do
      rating = CycloneDX::VulnerabilityRating.new(score: 15.0)
      vuln = CycloneDX::Vulnerability.new(id: "CVE-2024-1", ratings: [rating])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", vulnerabilities: [vuln])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("score") }.should be_true
    end

    it "detects invalid composition aggregate" do
      comp = CycloneDX::Composition.new(aggregate: "totally_made_up")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", compositions: [comp])
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("aggregate") }.should be_true
    end

    it "detects invalid lifecycle phase" do
      lc = CycloneDX::Lifecycle.new(phase: "bad-phase")
      metadata = CycloneDX::Metadata.new(lifecycles: [lc])
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.6", metadata: metadata)
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("phase") }.should be_true
    end

    it "validates nested sub-components" do
      sub = CycloneDX::Component.new(name: "sub", version: "1.0", component_type: "bad")
      parent = CycloneDX::Component.new(name: "parent", version: "1.0", components: [sub])
      bom = CycloneDX::BOM.new([parent], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path.includes?("components[0]") }.should be_true
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

    it "formats error messages with to_s" do
      comp = CycloneDX::Component.new(name: "", version: "1.0")
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom)
      validator.errors[0].to_s.should contain("$.components[0]")
    end
  end
end
