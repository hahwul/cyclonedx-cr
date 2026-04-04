require "spec"
require "../../src/cyclonedx/pedigree"

describe CycloneDX::Commit do
  it "serializes to JSON" do
    commit = CycloneDX::Commit.new(uid: "abc123", url: "https://github.com/example/repo/commit/abc123", message: "Fix bug")
    json = commit.to_json
    json.should contain(%("uid":"abc123"))
    json.should contain(%("message":"Fix bug"))
  end

  it "serializes to XML" do
    commit = CycloneDX::Commit.new(uid: "abc123", message: "Fix bug")
    xml_str = XML.build(indent: "  ") do |xml|
      commit.to_xml(xml)
    end
    xml_str.should contain("<commit>")
    xml_str.should contain("<uid>abc123</uid>")
    xml_str.should contain("<message>Fix bug</message>")
  end
end

describe CycloneDX::Patch do
  it "serializes to JSON" do
    patch = CycloneDX::Patch.new(patch_type: "backport")
    json = patch.to_json
    json.should contain(%("type":"backport"))
  end

  it "serializes to XML" do
    patch = CycloneDX::Patch.new(patch_type: "unofficial")
    xml_str = XML.build(indent: "  ") do |xml|
      patch.to_xml(xml)
    end
    xml_str.should contain(%(<patch type="unofficial"/>))
  end
end

describe CycloneDX::Pedigree do
  it "serializes to JSON" do
    commit = CycloneDX::Commit.new(uid: "abc123")
    patch = CycloneDX::Patch.new(patch_type: "cherry-pick")
    pedigree = CycloneDX::Pedigree.new(
      notes: "Patched for internal use",
      commits: [commit],
      patches: [patch],
    )
    json = pedigree.to_json
    json.should contain(%("notes":"Patched for internal use"))
    json.should contain(%("commits"))
    json.should contain(%("patches"))
  end

  it "serializes to XML" do
    commit = CycloneDX::Commit.new(uid: "abc123", message: "Initial")
    pedigree = CycloneDX::Pedigree.new(notes: "Supply chain notes", commits: [commit])

    xml_str = XML.build(indent: "  ") do |xml|
      pedigree.to_xml(xml)
    end
    xml_str.should contain("<pedigree>")
    xml_str.should contain("<commits>")
    xml_str.should contain("<uid>abc123</uid>")
    xml_str.should contain("<notes>Supply chain notes</notes>")
  end
end
