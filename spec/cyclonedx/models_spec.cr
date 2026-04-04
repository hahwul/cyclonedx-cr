require "spec"
require "../../src/cyclonedx/models"

describe CycloneDX::License do
  describe "#initialize" do
    it "can be initialized with an id" do
      license = CycloneDX::License.new(id: "MIT")
      license.id.should eq("MIT")
      license.name.should be_nil
      license.url.should be_nil
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
      license.url.should be_nil
    end

    it "can be initialized with a url" do
      license = CycloneDX::License.new(id: "MIT", url: "https://opensource.org/licenses/MIT")
      license.id.should eq("MIT")
      license.url.should eq("https://opensource.org/licenses/MIT")
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

    it "serializes url to JSON" do
      license = CycloneDX::License.new(id: "MIT", url: "https://opensource.org/licenses/MIT")
      json = license.to_json
      json.should contain(%("url":"https://opensource.org/licenses/MIT"))
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

    it "includes url in XML" do
      license = CycloneDX::License.new(id: "MIT", url: "https://opensource.org/licenses/MIT")
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain("<url>https://opensource.org/licenses/MIT</url>")
    end

    it "includes bom-ref and acknowledgement in XML" do
      license = CycloneDX::License.new(id: "MIT", bom_ref: "lic-1", acknowledgement: "declared")
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain(%(bom-ref="lic-1"))
      xml_str.should contain(%(acknowledgement="declared"))
    end

    it "includes attached text in XML" do
      text = CycloneDX::AttachedText.new(content: "MIT License text...", content_type: "text/plain", encoding: "base64")
      license = CycloneDX::License.new(id: "MIT", text: text)
      xml_str = XML.build(indent: "  ") do |xml|
        license.to_xml(xml)
      end
      xml_str.should contain(%(content-type="text/plain"))
      xml_str.should contain(%(encoding="base64"))
      xml_str.should contain("MIT License text...")
    end

    it "serializes bom-ref and acknowledgement to JSON" do
      license = CycloneDX::License.new(id: "MIT", bom_ref: "lic-1", acknowledgement: "concluded")
      json = license.to_json
      json.should contain(%("bom-ref":"lic-1"))
      json.should contain(%("acknowledgement":"concluded"))
    end
  end
end

describe CycloneDX::AttachedText do
  it "serializes to JSON" do
    text = CycloneDX::AttachedText.new(content: "license text", content_type: "text/plain")
    json = text.to_json
    json.should contain(%("content":"license text"))
    json.should contain(%("contentType":"text/plain"))
  end

  it "serializes to XML" do
    text = CycloneDX::AttachedText.new(content: "text content", content_type: "text/plain", encoding: "base64")
    xml_str = XML.build(indent: "  ") do |xml|
      text.to_xml(xml)
    end
    xml_str.should contain(%(content-type="text/plain"))
    xml_str.should contain(%(encoding="base64"))
    xml_str.should contain("text content")
  end
end

describe CycloneDX::Hash do
  describe "#initialize" do
    it "initializes with algorithm and content" do
      hash = CycloneDX::Hash.new(algorithm: "SHA-256", content: "abc123")
      hash.algorithm.should eq("SHA-256")
      hash.content.should eq("abc123")
    end
  end

  describe "#to_json" do
    it "serializes to JSON correctly" do
      hash = CycloneDX::Hash.new(algorithm: "SHA-256", content: "abc123")
      json = hash.to_json
      json.should contain(%("alg":"SHA-256"))
      json.should contain(%("content":"abc123"))
    end
  end

  describe "#to_xml" do
    it "serializes to XML correctly" do
      hash = CycloneDX::Hash.new(algorithm: "SHA-256", content: "abc123")
      xml_str = XML.build(indent: "  ") do |xml|
        hash.to_xml(xml)
      end
      xml_str.should contain(%(<hash alg="SHA-256">abc123</hash>))
    end
  end
end

describe CycloneDX::ExternalReference do
  describe "#initialize" do
    it "initializes with type and url" do
      ref = CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")
      ref.ref_type.should eq("website")
      ref.url.should eq("https://example.com")
      ref.comment.should be_nil
    end

    it "initializes with comment" do
      ref = CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/foo/bar", comment: "Main repo")
      ref.comment.should eq("Main repo")
    end
  end

  describe "#to_xml" do
    it "includes comment in XML" do
      ref = CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/foo/bar", comment: "Main repo")
      xml_str = XML.build(indent: "  ") do |xml|
        ref.to_xml(xml)
      end
      xml_str.should contain("<comment>Main repo</comment>")
    end
  end
end

describe CycloneDX::Dependency do
  describe "#initialize" do
    it "initializes with ref and empty dependsOn" do
      dep = CycloneDX::Dependency.new(ref: "my-lib@1.0.0")
      dep.ref.should eq("my-lib@1.0.0")
      dep.depends_on.should be_empty
    end

    it "initializes with dependsOn" do
      dep = CycloneDX::Dependency.new(ref: "my-app@1.0.0", depends_on: ["lib-a@1.0.0", "lib-b@2.0.0"])
      dep.depends_on.should eq(["lib-a@1.0.0", "lib-b@2.0.0"])
    end
  end

  describe "#to_json" do
    it "serializes to JSON correctly" do
      dep = CycloneDX::Dependency.new(ref: "my-app@1.0.0", depends_on: ["lib-a@1.0.0"])
      json = dep.to_json
      json.should contain(%("ref":"my-app@1.0.0"))
      json.should contain(%("dependsOn"))
      json.should contain(%("lib-a@1.0.0"))
    end

    it "serializes provides to JSON" do
      dep = CycloneDX::Dependency.new(ref: "my-lib@1.0.0", provides: ["virtual-api@1.0"])
      json = dep.to_json
      json.should contain(%("provides"))
      json.should contain(%("virtual-api@1.0"))
    end
  end

  describe "#to_xml" do
    it "serializes to XML correctly with dependsOn" do
      dep = CycloneDX::Dependency.new(ref: "my-app@1.0.0", depends_on: ["lib-a@1.0.0"])
      xml_str = XML.build(indent: "  ") do |xml|
        dep.to_xml(xml)
      end
      xml_str.should contain(%(<dependency ref="my-app@1.0.0">))
      xml_str.should contain(%(<dependency ref="lib-a@1.0.0"/>))
    end

    it "serializes to XML correctly without dependsOn" do
      dep = CycloneDX::Dependency.new(ref: "lib-a@1.0.0")
      xml_str = XML.build(indent: "  ") do |xml|
        dep.to_xml(xml)
      end
      xml_str.should contain(%(<dependency ref="lib-a@1.0.0"/>))
    end

    it "serializes provides to XML" do
      dep = CycloneDX::Dependency.new(ref: "my-lib@1.0.0", provides: ["virtual-api@1.0", "compat-layer@2.0"])
      xml_str = XML.build(indent: "  ") do |xml|
        dep.to_xml(xml)
      end
      xml_str.should contain(%(<provides ref="virtual-api@1.0"/>))
      xml_str.should contain(%(<provides ref="compat-layer@2.0"/>))
    end
  end
end

describe CycloneDX::Tool do
  describe "#to_json" do
    it "serializes correctly" do
      tool = CycloneDX::Tool.new(vendor: "v", name: "t", version: "1.0")
      json = tool.to_json
      json.should contain(%("vendor":"v"))
      json.should contain(%("name":"t"))
      json.should contain(%("version":"1.0"))
    end
  end

  describe "#to_xml" do
    it "serializes correctly" do
      tool = CycloneDX::Tool.new(vendor: "v", name: "t", version: "1.0")
      xml_str = XML.build(indent: "  ") do |xml|
        tool.to_xml(xml)
      end
      xml_str.should contain("<tool>")
      xml_str.should contain("<vendor>v</vendor>")
      xml_str.should contain("<name>t</name>")
      xml_str.should contain("<version>1.0</version>")
    end
  end
end

describe CycloneDX::Lifecycle do
  describe "#initialize" do
    it "initializes with a predefined phase" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      lc.phase.should eq("build")
      lc.name.should be_nil
    end

    it "initializes with a custom name and description" do
      lc = CycloneDX::Lifecycle.new(name: "staging", description: "Pre-production environment")
      lc.phase.should be_nil
      lc.name.should eq("staging")
      lc.description.should eq("Pre-production environment")
    end
  end

  describe "#to_json" do
    it "serializes correctly" do
      lc = CycloneDX::Lifecycle.new(phase: "operations")
      json = lc.to_json
      json.should contain(%("phase":"operations"))
    end
  end

  describe "#to_xml" do
    it "serializes with phase" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      xml_str = XML.build(indent: "  ") do |xml|
        lc.to_xml(xml)
      end
      xml_str.should contain("<lifecycle>")
      xml_str.should contain("<phase>build</phase>")
    end

    it "serializes with custom name" do
      lc = CycloneDX::Lifecycle.new(name: "staging", description: "Staging env")
      xml_str = XML.build(indent: "  ") do |xml|
        lc.to_xml(xml)
      end
      xml_str.should contain("<name>staging</name>")
      xml_str.should contain("<description>Staging env</description>")
    end
  end
end

describe CycloneDX::OrganizationalEntity do
  describe "#initialize" do
    it "initializes with all fields" do
      contact = CycloneDX::OrganizationalContact.new(name: "John", email: "john@example.com")
      entity = CycloneDX::OrganizationalEntity.new(
        name: "Example Corp",
        url: ["https://example.com"],
        contact: [contact]
      )
      entity.name.should eq("Example Corp")
      entity.url.should eq(["https://example.com"])
      entity.contact.not_nil!.size.should eq(1)
    end
  end

  describe "#to_json" do
    it "serializes correctly" do
      entity = CycloneDX::OrganizationalEntity.new(name: "Corp", url: ["https://corp.com"])
      json = entity.to_json
      json.should contain(%("name":"Corp"))
      json.should contain(%("url"))
      json.should contain(%("https://corp.com"))
    end
  end

  describe "#to_xml" do
    it "serializes with custom element name" do
      entity = CycloneDX::OrganizationalEntity.new(name: "Corp", url: ["https://corp.com"])
      xml_str = XML.build(indent: "  ") do |xml|
        entity.to_xml(xml, "supplier")
      end
      xml_str.should contain("<supplier>")
      xml_str.should contain("<name>Corp</name>")
      xml_str.should contain("<url>https://corp.com</url>")
    end
  end
end

describe CycloneDX::Property do
  describe "#initialize" do
    it "initializes with name and value" do
      prop = CycloneDX::Property.new(name: "cdx:tool:name", value: "my-tool")
      prop.name.should eq("cdx:tool:name")
      prop.value.should eq("my-tool")
    end

    it "initializes with name only" do
      prop = CycloneDX::Property.new(name: "cdx:flag")
      prop.name.should eq("cdx:flag")
      prop.value.should be_nil
    end
  end

  describe "#to_json" do
    it "serializes to JSON correctly" do
      prop = CycloneDX::Property.new(name: "cdx:tool:name", value: "my-tool")
      json = prop.to_json
      json.should contain(%("name":"cdx:tool:name"))
      json.should contain(%("value":"my-tool"))
    end

    it "serializes nil value to JSON" do
      prop = CycloneDX::Property.new(name: "cdx:flag")
      json = prop.to_json
      json.should contain(%("name":"cdx:flag"))
    end
  end

  describe "#to_xml" do
    it "serializes to XML correctly" do
      prop = CycloneDX::Property.new(name: "cdx:tool:name", value: "my-tool")
      xml_str = XML.build(indent: "  ") do |xml|
        prop.to_xml(xml)
      end
      xml_str.should contain(%(<property name="cdx:tool:name">my-tool</property>))
    end

    it "serializes empty property to XML" do
      prop = CycloneDX::Property.new(name: "cdx:flag")
      xml_str = XML.build(indent: "  ") do |xml|
        prop.to_xml(xml)
      end
      xml_str.should contain(%(<property name="cdx:flag"/>))
    end
  end
end

describe CycloneDX::OrganizationalContact do
  describe "#to_json" do
    it "serializes correctly" do
      contact = CycloneDX::OrganizationalContact.new(name: "John", email: "john@example.com", phone: "123")
      json = contact.to_json
      json.should contain(%("name":"John"))
      json.should contain(%("email":"john@example.com"))
      json.should contain(%("phone":"123"))
    end
  end

  describe "#to_xml" do
    it "serializes correctly" do
      contact = CycloneDX::OrganizationalContact.new(name: "John", email: "john@example.com")
      xml_str = XML.build(indent: "  ") do |xml|
        contact.to_xml(xml)
      end
      xml_str.should contain("<author>")
      xml_str.should contain("<name>John</name>")
      xml_str.should contain("<email>john@example.com</email>")
    end
  end
end
