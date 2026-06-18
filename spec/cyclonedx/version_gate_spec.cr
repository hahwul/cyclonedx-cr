require "spec"
require "../../src/cyclonedx/bom"
require "../../src/cyclonedx/metadata"
require "../../src/cyclonedx/validator"
require "../../src/cyclonedx/annotation"
require "../../src/cyclonedx/declaration"

# Normalises a serialized BOM so two outputs can be compared on their *core*
# structure only (the per-version `specVersion` and the random `serialNumber`
# are masked out).
private def normalize_core(json : String) : String
  json
    .gsub(/"specVersion":"[^"]+"/, %("specVersion":"X"))
    .gsub(/"serialNumber":"[^"]+"/, %("serialNumber":"X"))
end

# Builds a bare "shards-generator"-shaped BOM using only core fields.
private def core_bom(version : String) : CycloneDX::BOM
  tool = CycloneDX::Tool.new(vendor: "hahwul", name: "cyclonedx-cr", version: "1.3.0")
  main = CycloneDX::Component.new(
    component_type: "application", name: "myapp", version: "1.0",
    licenses: [CycloneDX::License.new(id: "MIT")] of CycloneDX::License | CycloneDX::LicenseExpression,
    external_references: [CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/x/y")],
    bom_ref: "myapp@1.0"
  )
  md = CycloneDX::Metadata.new(component: main, tools: [tool], timestamp: "2024-01-01T00:00:00Z")
  dep = CycloneDX::Component.new(
    name: "lib-a", version: "2.0", purl: "pkg:github/x/a@2.0",
    bom_ref: "lib-a@2.0", scope: "required",
    hashes: [CycloneDX::Hash.new(algorithm: "SHA-256", content: "deadbeef")]
  )
  graph = [
    CycloneDX::Dependency.new(ref: "myapp@1.0", depends_on: ["lib-a@2.0"]),
    CycloneDX::Dependency.new(ref: "lib-a@2.0"),
  ]
  CycloneDX::BOM.new([dep], version, metadata: md, dependencies: graph)
end

# Builds a one-component BOM whose only license is a `LicenseExpression`
# carrying the 1.6-only `bom-ref` and `acknowledgement` fields.
private def expr_bom(version : String) : CycloneDX::BOM
  expr = CycloneDX::LicenseExpression.new(
    expression: "MIT OR Apache-2.0", bom_ref: "expr-1", acknowledgement: "concluded"
  )
  comp = CycloneDX::Component.new(
    name: "lib", version: "1.0",
    licenses: [expr] of CycloneDX::License | CycloneDX::LicenseExpression
  )
  CycloneDX::BOM.new([comp], version)
end

describe CycloneDX::VersionGate do
  describe "(a) metadata.lifecycles / bom.annotations gating" do
    it "does NOT emit lifecycles or annotations when declared as 1.4" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      md = CycloneDX::Metadata.new(lifecycles: [lc], timestamp: "2024-01-01T00:00:00Z")
      ann = CycloneDX::Annotation.new(text: "Reviewed")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.4", metadata: md, annotations: [ann])

      json = bom.to_json
      json.should_not contain(%("lifecycles"))
      json.should_not contain(%("annotations"))

      xml = bom.to_xml
      xml.should_not contain("<lifecycles>")
      xml.should_not contain("<annotations>")
    end

    it "DOES emit lifecycles and annotations when declared as 1.5" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      md = CycloneDX::Metadata.new(lifecycles: [lc], timestamp: "2024-01-01T00:00:00Z")
      ann = CycloneDX::Annotation.new(text: "Reviewed")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.5", metadata: md, annotations: [ann])

      json = bom.to_json
      json.should contain(%("lifecycles"))
      json.should contain(%("annotations"))

      xml = bom.to_xml
      xml.should contain("<lifecycles>")
      xml.should contain("<annotations>")
    end
  end

  describe "(b) 1.6-only component / license fields gated under 1.4 and 1.5" do
    it "strips component tags, cryptoProperties, authors array, and license bom-ref under 1.4" do
      comp = CycloneDX::Component.new(
        name: "lib", version: "1.0.0",
        tags: ["a", "b"],
        authors: [CycloneDX::OrganizationalContact.new(name: "Jane")],
        crypto_properties: CycloneDX::CryptoProperties.new(asset_type: "algorithm"),
        author: "single-author-string",
        licenses: [CycloneDX::License.new(id: "MIT", bom_ref: "lic-1", acknowledgement: "declared")] of CycloneDX::License | CycloneDX::LicenseExpression
      )
      bom = CycloneDX::BOM.new([comp], "1.4")

      json = bom.to_json
      json.should_not contain(%("tags"))
      json.should_not contain(%("cryptoProperties"))
      json.should_not contain(%("authors"))
      json.should_not contain(%("bom-ref":"lic-1"))
      json.should_not contain(%("acknowledgement"))
      # the single `author` string is older than 1.6 and must be kept
      json.should contain(%("author":"single-author-string"))

      xml = bom.to_xml
      xml.should_not contain("<tags>")
      xml.should_not contain("<authors>")
      xml.should_not contain("<cryptoProperties>")
      xml.should_not contain(%(bom-ref="lic-1"))
      xml.should_not contain("acknowledgement=")
      xml.should contain("<author>single-author-string</author>")
    end

    it "strips 1.6-only fields under 1.5 but keeps 1.5 fields (modelCard, license bom-ref)" do
      comp = CycloneDX::Component.new(
        name: "lib", version: "1.0.0",
        tags: ["a"],
        authors: [CycloneDX::OrganizationalContact.new(name: "Jane")],
        crypto_properties: CycloneDX::CryptoProperties.new(asset_type: "algorithm"),
        model_card: CycloneDX::ModelCard.new(bom_ref: "mc-1"),
        licenses: [CycloneDX::License.new(id: "MIT", bom_ref: "lic-1", acknowledgement: "declared")] of CycloneDX::License | CycloneDX::LicenseExpression
      )
      bom = CycloneDX::BOM.new([comp], "1.5")

      json = bom.to_json
      json.should_not contain(%("tags"))
      json.should_not contain(%("cryptoProperties"))
      json.should_not contain(%("authors"))
      # license bom-ref is a 1.5 field, so it is kept at 1.5 ...
      json.should contain(%("bom-ref":"lic-1"))
      # ... but acknowledgement is 1.6-only, so it is stripped at 1.5
      json.should_not contain(%("acknowledgement"))
      # modelCard is 1.5+, so it stays at 1.5
      json.should contain(%("modelCard"))
    end

    it "emits all 1.6 fields when declared as 1.6" do
      comp = CycloneDX::Component.new(
        name: "lib", version: "1.0.0",
        tags: ["a"],
        authors: [CycloneDX::OrganizationalContact.new(name: "Jane")],
        crypto_properties: CycloneDX::CryptoProperties.new(asset_type: "algorithm"),
        licenses: [CycloneDX::License.new(id: "MIT", bom_ref: "lic-1", acknowledgement: "declared")] of CycloneDX::License | CycloneDX::LicenseExpression
      )
      bom = CycloneDX::BOM.new([comp], "1.6")

      json = bom.to_json
      json.should contain(%("tags"))
      json.should contain(%("cryptoProperties"))
      json.should contain(%("authors"))
      json.should contain(%("bom-ref":"lic-1"))
      json.should contain(%("acknowledgement"))
    end
  end

  describe "(c) bare shards-generator output stays schema-shaped across versions" do
    it "produces identical core JSON for 1.4 / 1.5 / 1.6" do
      j14 = normalize_core(core_bom("1.4").to_json)
      j15 = normalize_core(core_bom("1.5").to_json)
      j16 = normalize_core(core_bom("1.6").to_json)

      j14.should eq(j15)
      j15.should eq(j16)
    end

    it "keeps all core fields present at every version" do
      %w[1.4 1.5 1.6].each do |v|
        json = core_bom(v).to_json
        json.should contain(%("bomFormat":"CycloneDX"))
        json.should contain(%("specVersion":"#{v}"))
        json.should contain(%("serialNumber":"urn:uuid:))
        json.should contain(%("timestamp"))
        json.should contain(%("tools"))
        json.should contain(%("bom-ref":"myapp@1.0"))
        json.should contain(%("type":"application"))
        json.should contain(%("purl":"pkg:github/x/a@2.0"))
        json.should contain(%("scope":"required"))
        json.should contain(%("licenses"))
        json.should contain(%("hashes"))
        json.should contain(%("externalReferences"))
        json.should contain(%("dependencies"))
      end
    end

    it "produces a bare BOM that has no gating violations at any version" do
      %w[1.4 1.5 1.6].each do |v|
        validator = CycloneDX::Validator.new
        validator.validate(core_bom(v)).should be_true
        validator.errors.should be_empty
      end
    end
  end

  describe "(d) validator flags a 1.6 field set under specVersion 1.4" do
    it "reports gating errors for component and bom-level 1.6 fields" do
      comp = CycloneDX::Component.new(
        name: "lib", version: "1.0.0",
        tags: ["a"],
        crypto_properties: CycloneDX::CryptoProperties.new(asset_type: "algorithm"),
        authors: [CycloneDX::OrganizationalContact.new(name: "Jane")]
      )
      defs = CycloneDX::Definitions.new(standards: [CycloneDX::DefinitionStandard.new(name: "NIST")])
      bom = CycloneDX::BOM.new([comp], "1.4", definitions: defs)

      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false

      messages = validator.errors.map(&.message)
      validator.errors.any? { |e| e.path == "$.components[0].tags" }.should be_true
      validator.errors.any? { |e| e.path == "$.components[0].cryptoProperties" }.should be_true
      validator.errors.any? { |e| e.path == "$.components[0].authors" }.should be_true
      validator.errors.any? { |e| e.path == "$.definitions" }.should be_true
      messages.all?(&.includes?("specVersion")).should be_true
    end

    it "reports a 1.5 field (lifecycles/annotations) under 1.4" do
      lc = CycloneDX::Lifecycle.new(phase: "build")
      md = CycloneDX::Metadata.new(lifecycles: [lc])
      ann = CycloneDX::Annotation.new(text: "note")
      bom = CycloneDX::BOM.new([] of CycloneDX::Component, "1.4", metadata: md, annotations: [ann])

      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_false
      validator.errors.any? { |e| e.path == "$.metadata.lifecycles" }.should be_true
      validator.errors.any? { |e| e.path == "$.annotations" }.should be_true
    end

    it "does NOT flag those fields when the declared version supports them" do
      comp = CycloneDX::Component.new(
        name: "lib", version: "1.0.0",
        tags: ["a"],
        crypto_properties: CycloneDX::CryptoProperties.new(asset_type: "algorithm")
      )
      bom = CycloneDX::BOM.new([comp], "1.6")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
      validator.errors.should be_empty
    end

    it "does NOT flag the single component.author string under 1.4" do
      comp = CycloneDX::Component.new(name: "lib", version: "1.0.0", author: "Jane Doe")
      bom = CycloneDX::BOM.new([comp], "1.4")
      validator = CycloneDX::Validator.new
      validator.validate(bom).should be_true
    end
  end

  describe "(f) LicenseExpression bom-ref/acknowledgement gating (1.6+)" do
    it "strips bom-ref/acknowledgement from a LicenseExpression in 1.4 JSON" do
      json = expr_bom("1.4").to_json
      json.should contain(%("expression":"MIT OR Apache-2.0"))
      json.should_not contain(%("bom-ref":"expr-1"))
      json.should_not contain(%("acknowledgement"))
    end

    it "strips bom-ref/acknowledgement attributes from an <expression> in 1.4 XML" do
      xml = expr_bom("1.4").to_xml
      xml.should contain("MIT OR Apache-2.0")
      xml.should_not contain(%(bom-ref="expr-1"))
      xml.should_not contain("acknowledgement")
    end

    it "keeps bom-ref/acknowledgement on a LicenseExpression in 1.6 JSON" do
      json = expr_bom("1.6").to_json
      json.should contain(%("bom-ref":"expr-1"))
      json.should contain(%("acknowledgement":"concluded"))
    end

    it "reports validator violations that the filters actually strip (consistency)" do
      validator = CycloneDX::Validator.new
      validator.validate(expr_bom("1.4")).should be_false
      validator.errors.any?(&.path.includes?("bom-ref")).should be_true
      validator.errors.any?(&.path.includes?("acknowledgement")).should be_true
    end
  end
end
