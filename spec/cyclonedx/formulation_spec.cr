require "spec"
require "../../src/cyclonedx/formulation"

describe CycloneDX::TaskStep do
  it "serializes to XML" do
    step = CycloneDX::TaskStep.new(name: "compile", commands: ["crystal build src/main.cr"])
    xml_str = XML.build(indent: "  ") do |xml|
      step.to_xml(xml)
    end
    xml_str.should contain("<step>")
    xml_str.should contain("<name>compile</name>")
    xml_str.should contain("<command>crystal build src/main.cr</command>")
  end
end

describe CycloneDX::Task do
  it "serializes to JSON" do
    task = CycloneDX::Task.new(
      uid: "task-1",
      name: "build",
      task_types: ["build", "test"],
      bom_ref: "task-ref-1",
    )
    json = task.to_json
    json.should contain(%("uid":"task-1"))
    json.should contain(%("name":"build"))
    json.should contain(%("taskTypes"))
    json.should contain(%("bom-ref":"task-ref-1"))
  end

  it "serializes to XML" do
    step = CycloneDX::TaskStep.new(name: "compile")
    task = CycloneDX::Task.new(
      uid: "task-1",
      name: "build",
      task_types: ["build"],
      steps: [step],
    )
    xml_str = XML.build(indent: "  ") do |xml|
      task.to_xml(xml)
    end
    xml_str.should contain("<task>")
    xml_str.should contain("<uid>task-1</uid>")
    xml_str.should contain("<taskTypes>")
    xml_str.should contain("<taskType>build</taskType>")
    xml_str.should contain("<steps>")
  end
end

describe CycloneDX::Workflow do
  it "serializes to XML with tasks" do
    task = CycloneDX::Task.new(uid: "t1", name: "lint", task_types: ["lint"])
    wf = CycloneDX::Workflow.new(uid: "wf-1", name: "CI Pipeline", tasks: [task])
    xml_str = XML.build(indent: "  ") do |xml|
      wf.to_xml(xml)
    end
    xml_str.should contain("<workflow>")
    xml_str.should contain("<uid>wf-1</uid>")
    xml_str.should contain("<name>CI Pipeline</name>")
    xml_str.should contain("<tasks>")
  end
end

describe CycloneDX::Formula do
  it "serializes to JSON" do
    task = CycloneDX::Task.new(name: "build", task_types: ["build"])
    wf = CycloneDX::Workflow.new(uid: "wf-1", tasks: [task])
    formula = CycloneDX::Formula.new(bom_ref: "formula-1", workflows: [wf])
    json = formula.to_json
    json.should contain(%("bom-ref":"formula-1"))
    json.should contain(%("workflows"))
  end

  it "serializes to XML" do
    wf = CycloneDX::Workflow.new(uid: "wf-1", name: "build")
    formula = CycloneDX::Formula.new(workflows: [wf])
    xml_str = XML.build(indent: "  ") do |xml|
      formula.to_xml(xml)
    end
    xml_str.should contain("<formula>")
    xml_str.should contain("<workflows>")
    xml_str.should contain("<uid>wf-1</uid>")
  end
end
