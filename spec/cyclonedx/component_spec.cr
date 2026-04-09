require "spec"
require "../../src/cyclonedx/component"

describe CycloneDX::Component do
  describe "#initialize" do
    it "initializes with required arguments" do
      component = CycloneDX::Component.new(name: "my-lib", version: "1.0.0")
      component.name.should eq "my-lib"
      component.version.should eq "1.0.0"
      component.component_type.should eq "library"
      component.purl.should be_nil
      component.description.should be_nil
      component.author.should be_nil
      component.licenses.should be_nil
      component.external_references.should be_nil
      component.bom_ref.should be_nil
      component.scope.should be_nil
      component.hashes.should be_nil
      component.properties.should be_nil
    end

    it "initializes with all arguments" do
      licenses = [CycloneDX::License.new(name: "MIT")] of CycloneDX::License | CycloneDX::LicenseExpression
      refs = [CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")]
      hashes = [CycloneDX::Hash.new(algorithm: "SHA-256", content: "abc123")]
      component = CycloneDX::Component.new(
        name: "my-app",
        version: "2.0.0",
        component_type: "application",
        purl: "pkg:gem/my-app@2.0.0",
        description: "A test app",
        author: "John Doe",
        licenses: licenses,
        external_references: refs,
        bom_ref: "my-app@2.0.0",
        scope: "required",
        hashes: hashes
      )

      component.name.should eq "my-app"
      component.version.should eq "2.0.0"
      component.component_type.should eq "application"
      component.purl.should eq "pkg:gem/my-app@2.0.0"
      component.description.should eq "A test app"
      component.author.should eq "John Doe"
      component.licenses.should eq licenses
      component.external_references.should eq refs
      component.bom_ref.should eq "my-app@2.0.0"
      component.scope.should eq "required"
      component.hashes.should eq hashes
    end
  end

  describe "#to_json" do
    it "serializes to JSON correctly" do
      licenses = [CycloneDX::License.new(name: "MIT")] of CycloneDX::License | CycloneDX::LicenseExpression
      refs = [CycloneDX::ExternalReference.new(ref_type: "website", url: "https://example.com")]
      component = CycloneDX::Component.new(
        name: "json-lib",
        version: "3.0.0",
        component_type: "library",
        purl: "pkg:npm/json-lib@3.0.0",
        description: "JSON lib",
        author: "Jane Doe",
        licenses: licenses,
        external_references: refs,
        bom_ref: "json-lib@3.0.0",
        scope: "required"
      )

      json = component.to_json
      json.should contain %("bom-ref":"json-lib@3.0.0")
      json.should contain %("type":"library")
      json.should contain %("name":"json-lib")
      json.should contain %("version":"3.0.0")
      json.should contain %("purl":"pkg:npm/json-lib@3.0.0")
      json.should contain %("description":"JSON lib")
      json.should contain %("author":"Jane Doe")
      json.should contain %("scope":"required")
      json.should contain %("licenses")
      json.should contain %("MIT")
      json.should contain %("externalReferences")
      json.should contain %("website")
      json.should contain %("https://example.com")
    end
  end

  describe "#to_xml" do
    it "serializes to XML correctly" do
      licenses = [CycloneDX::License.new(name: "Apache-2.0")] of CycloneDX::License | CycloneDX::LicenseExpression
      refs = [CycloneDX::ExternalReference.new(ref_type: "vcs", url: "https://github.com/example/xml-lib")]
      hashes = [CycloneDX::Hash.new(algorithm: "SHA-256", content: "abc123")]
      component = CycloneDX::Component.new(
        name: "xml-lib",
        version: "4.0.0",
        component_type: "library",
        purl: "pkg:maven/xml-lib@4.0.0",
        description: "XML lib",
        author: "Xml Author",
        licenses: licenses,
        external_references: refs,
        bom_ref: "xml-lib@4.0.0",
        scope: "required",
        hashes: hashes
      )

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<component type="library" bom-ref="xml-lib@4.0.0">)
      xml_content.should contain %(<name>xml-lib</name>)
      xml_content.should contain %(<version>4.0.0</version>)
      xml_content.should contain %(<purl>pkg:maven/xml-lib@4.0.0</purl>)
      xml_content.should contain %(<description>XML lib</description>)
      xml_content.should contain %(<author>Xml Author</author>)
      xml_content.should contain %(<scope>required</scope>)
      xml_content.should contain %(<hashes>)
      xml_content.should contain %(<hash alg="SHA-256">abc123</hash>)
      xml_content.should contain %(<licenses>)
      xml_content.should contain %(<license>)
      xml_content.should contain %(<name>Apache-2.0</name>)
      xml_content.should contain %(<externalReferences>)
      xml_content.should contain %(<reference type="vcs">)
      xml_content.should contain %(<url>https://github.com/example/xml-lib</url>)
    end

    it "outputs purl before hashes in XML (spec order)" do
      hashes = [CycloneDX::Hash.new(algorithm: "SHA-256", content: "abc123")]
      component = CycloneDX::Component.new(
        name: "lib", version: "1.0.0",
        purl: "pkg:github/owner/lib@1.0.0",
        cpe: "cpe:2.3:a:owner:lib:1.0.0",
        hashes: hashes,
      )
      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      purl_pos = xml_content.index("<purl>").not_nil!
      hashes_pos = xml_content.index("<hashes>").not_nil!
      purl_pos.should be < hashes_pos
    end

    it "handles optional fields being nil in XML" do
      component = CycloneDX::Component.new(name: "minimal", version: "0.1.0")

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<component type="library">)
      xml_content.should contain %(<name>minimal</name>)
      xml_content.should contain %(<version>0.1.0</version>)
      xml_content.should_not contain %(<purl>)
      xml_content.should_not contain %(<description>)
      xml_content.should_not contain %(<author>)
      xml_content.should_not contain %(<licenses>)
      xml_content.should_not contain %(<externalReferences>)
      xml_content.should_not contain %(bom-ref)
      xml_content.should_not contain %(<scope>)
      xml_content.should_not contain %(<hashes>)
      xml_content.should_not contain %(<properties>)
    end

    it "serializes properties to XML" do
      props = [CycloneDX::Property.new(name: "cdx:tool:name", value: "test")]
      component = CycloneDX::Component.new(name: "lib", version: "1.0.0", properties: props)

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<properties>)
      xml_content.should contain %(<property name="cdx:tool:name">test</property>)
    end
  end

  describe "expanded spec fields" do
    it "serializes new spec fields to XML" do
      supplier = CycloneDX::OrganizationalEntity.new(name: "Supplier Inc")
      component = CycloneDX::Component.new(
        name: "full-lib",
        version: "1.0.0",
        group: "com.example",
        copyright: "Copyright 2024 Example",
        cpe: "cpe:2.3:a:example:full-lib:1.0.0:*:*:*:*:*:*:*",
        publisher: "Example Publisher",
        supplier: supplier,
        tags: ["security", "crypto"],
      )

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<group>com.example</group>)
      xml_content.should contain %(<copyright>Copyright 2024 Example</copyright>)
      xml_content.should contain %(<cpe>cpe:2.3:a:example:full-lib:1.0.0:*:*:*:*:*:*:*</cpe>)
      xml_content.should contain %(<publisher>Example Publisher</publisher>)
      xml_content.should contain %(<supplier>)
      xml_content.should contain %(<name>Supplier Inc</name>)
      xml_content.should contain %(<tags>)
      xml_content.should contain %(<tag>security</tag>)
      xml_content.should contain %(<tag>crypto</tag>)
    end

    it "serializes nested sub-components to XML" do
      sub = CycloneDX::Component.new(name: "sub-lib", version: "0.1.0")
      component = CycloneDX::Component.new(name: "parent", version: "1.0.0", components: [sub])

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end

      xml_content.should contain %(<components>)
      xml_content.should contain %(<name>sub-lib</name>)
    end

    it "serializes new spec fields to JSON" do
      component = CycloneDX::Component.new(
        name: "json-test",
        version: "1.0.0",
        group: "com.example",
        copyright: "Copyright 2024",
        cpe: "cpe:2.3:a:example:json-test:1.0.0",
        publisher: "Pub",
        tags: ["tag1"],
        omnibor_id: ["gitoid:blob:sha256:abc"],
        swhid: ["swh:1:cnt:abc"],
      )

      json = component.to_json
      json.should contain %("group":"com.example")
      json.should contain %("copyright":"Copyright 2024")
      json.should contain %("cpe":"cpe:2.3:a:example:json-test:1.0.0")
      json.should contain %("publisher":"Pub")
      json.should contain %("tags")
      json.should contain %("tag1")
      json.should contain %("omniborId")
      json.should contain %("swhid")
    end
  end

  describe "new CycloneDX spec fields" do
    it "serializes authors (OrganizationalContact array) to JSON and XML" do
      authors = [
        CycloneDX::OrganizationalContact.new(name: "Alice", email: "alice@example.com"),
        CycloneDX::OrganizationalContact.new(name: "Bob"),
      ]
      component = CycloneDX::Component.new(name: "lib", version: "1.0.0", authors: authors)

      json = component.to_json
      json.should contain(%("authors"))
      json.should contain(%("Alice"))
      json.should contain(%("alice@example.com"))

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      xml_content.should contain(%(<authors>))
      xml_content.should contain(%(<name>Alice</name>))
      xml_content.should contain(%(<email>alice@example.com</email>))
    end

    it "serializes swid to JSON and XML" do
      swid = CycloneDX::Swid.new(tag_id: "swidgen-242eb18a-503e-ca37", name: "my-lib", version: "1.0.0")
      component = CycloneDX::Component.new(name: "my-lib", version: "1.0.0", swid: swid)

      json = component.to_json
      json.should contain(%("swid"))
      json.should contain(%("tagId":"swidgen-242eb18a-503e-ca37"))

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      xml_content.should contain(%(<swid tagId="swidgen-242eb18a-503e-ca37" name="my-lib" version="1.0.0"))
    end

    it "serializes releaseNotes to JSON and XML" do
      rn = CycloneDX::ReleaseNotes.new(
        release_type: "major",
        title: "v2.0.0",
        description: "Major release with breaking changes",
        timestamp: "2024-01-01T00:00:00Z",
        tags: ["breaking", "security"],
      )
      component = CycloneDX::Component.new(name: "lib", version: "2.0.0", release_notes: rn)

      json = component.to_json
      json.should contain(%("releaseNotes"))
      json.should contain(%("type":"major"))
      json.should contain(%("title":"v2.0.0"))

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      xml_content.should contain(%(<releaseNotes>))
      xml_content.should contain(%(<type>major</type>))
      xml_content.should contain(%(<title>v2.0.0</title>))
      xml_content.should contain(%(<description>Major release with breaking changes</description>))
      xml_content.should contain(%(<tag>breaking</tag>))
    end

    it "serializes modelCard to JSON and XML" do
      params = CycloneDX::ModelParameters.new(
        task: "text-classification",
        architecture_family: "transformer",
      )
      mc = CycloneDX::ModelCard.new(bom_ref: "mc-1", model_parameters: params)
      component = CycloneDX::Component.new(
        name: "sentiment-model", version: "1.0.0",
        component_type: "machine-learning-model", model_card: mc,
      )

      json = component.to_json
      json.should contain(%("modelCard"))
      json.should contain(%("task":"text-classification"))

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      xml_content.should contain(%(<modelCard bom-ref="mc-1">))
      xml_content.should contain(%(<modelParameters>))
      xml_content.should contain(%(<task>text-classification</task>))
      xml_content.should contain(%(<architectureFamily>transformer</architectureFamily>))
    end

    it "serializes data to JSON and XML" do
      data = [CycloneDX::ComponentData.new(data_type: "dataset", name: "training-data")]
      component = CycloneDX::Component.new(
        name: "data-component", version: "1.0.0",
        component_type: "data", data: data,
      )

      json = component.to_json
      json.should contain(%("data"))
      json.should contain(%("training-data"))

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      xml_content.should contain(%(<data>))
      xml_content.should contain(%(<name>training-data</name>))
    end

    it "serializes cryptoProperties to JSON and XML" do
      algo = CycloneDX::AlgorithmProperties.new(
        primitive: "ae", mode: "gcm", padding: "pkcs7",
        crypto_functions: ["encrypt", "decrypt"],
      )
      crypto = CycloneDX::CryptoProperties.new(
        asset_type: "algorithm", algorithm_properties: algo, oid: "2.16.840.1.101.3.4.1.6",
      )
      component = CycloneDX::Component.new(
        name: "aes-256-gcm", version: "1.0.0",
        component_type: "cryptographic-asset", crypto_properties: crypto,
      )

      json = component.to_json
      json.should contain(%("cryptoProperties"))
      json.should contain(%("assetType":"algorithm"))
      json.should contain(%("primitive":"ae"))
      json.should contain(%("oid":"2.16.840.1.101.3.4.1.6"))

      xml_content = XML.build(indent: "  ") do |xml|
        component.to_xml(xml)
      end
      xml_content.should contain(%(<cryptoProperties>))
      xml_content.should contain(%(<assetType>algorithm</assetType>))
      xml_content.should contain(%(<algorithmProperties>))
      xml_content.should contain(%(<primitive>ae</primitive>))
      xml_content.should contain(%(<mode>gcm</mode>))
      xml_content.should contain(%(<cryptoFunctions>))
      xml_content.should contain(%(<cryptoFunction>encrypt</cryptoFunction>))
      xml_content.should contain(%(<oid>2.16.840.1.101.3.4.1.6</oid>))
    end
  end

  describe "scope validation" do
    it "accepts valid scopes" do
      %w[required optional excluded].each do |scope|
        component = CycloneDX::Component.new(name: "lib", version: "1.0", scope: scope)
        component.scope.should eq(scope)
      end
    end

    it "accepts nil scope" do
      component = CycloneDX::Component.new(name: "lib", version: "1.0")
      component.scope.should be_nil
    end

    it "raises on invalid scope" do
      expect_raises(ArgumentError, "Invalid scope") do
        CycloneDX::Component.new(name: "lib", version: "1.0", scope: "invalid")
      end
    end
  end
end
