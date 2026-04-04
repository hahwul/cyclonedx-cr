require "spec"
require "../../src/cyclonedx/service"

describe CycloneDX::DataClassification do
  it "serializes to JSON" do
    dc = CycloneDX::DataClassification.new(flow: "outbound", classification: "PII")
    json = dc.to_json
    json.should contain(%("flow":"outbound"))
    json.should contain(%("classification":"PII"))
  end

  it "serializes to XML" do
    dc = CycloneDX::DataClassification.new(flow: "inbound", classification: "public")
    xml_str = XML.build(indent: "  ") do |xml|
      dc.to_xml(xml)
    end
    xml_str.should contain(%(<classification flow="inbound">public</classification>))
  end
end

describe CycloneDX::Service do
  describe "#initialize" do
    it "initializes with required name only" do
      svc = CycloneDX::Service.new(name: "auth-service")
      svc.name.should eq("auth-service")
      svc.version.should be_nil
      svc.endpoints.should be_nil
      svc.authenticated.should be_nil
    end

    it "initializes with all fields" do
      provider = CycloneDX::OrganizationalEntity.new(name: "Cloud Corp")
      data = [CycloneDX::DataClassification.new(flow: "bi-directional", classification: "PII")]
      svc = CycloneDX::Service.new(
        name: "api-gateway",
        version: "2.0.0",
        bom_ref: "api-gateway-ref",
        provider: provider,
        group: "com.example",
        description: "API Gateway",
        endpoints: ["https://api.example.com/v2"],
        authenticated: true,
        x_trust_boundary: true,
        trust_zone: "external",
        data: data,
        tags: ["api", "gateway"],
      )

      svc.bom_ref.should eq("api-gateway-ref")
      svc.provider.not_nil!.name.should eq("Cloud Corp")
      svc.authenticated.should eq(true)
      svc.x_trust_boundary.should eq(true)
      svc.trust_zone.should eq("external")
      svc.tags.should eq(["api", "gateway"])
    end
  end

  describe "#to_json" do
    it "serializes correctly" do
      svc = CycloneDX::Service.new(
        name: "auth",
        version: "1.0.0",
        bom_ref: "auth-ref",
        endpoints: ["https://auth.example.com"],
        authenticated: true,
        x_trust_boundary: false,
      )

      json = svc.to_json
      json.should contain(%("bom-ref":"auth-ref"))
      json.should contain(%("name":"auth"))
      json.should contain(%("version":"1.0.0"))
      json.should contain(%("endpoints"))
      json.should contain(%("https://auth.example.com"))
      json.should contain(%("authenticated":true))
      json.should contain(%("x-trust-boundary":false))
    end
  end

  describe "#to_xml" do
    it "serializes correctly" do
      provider = CycloneDX::OrganizationalEntity.new(name: "Corp")
      data = [CycloneDX::DataClassification.new(flow: "outbound", classification: "PII")]
      svc = CycloneDX::Service.new(
        name: "user-service",
        version: "1.0.0",
        bom_ref: "svc-ref",
        provider: provider,
        group: "com.example",
        description: "User management",
        endpoints: ["https://users.example.com"],
        authenticated: true,
        x_trust_boundary: true,
        trust_zone: "internal",
        data: data,
        tags: ["users"],
      )

      xml_str = XML.build(indent: "  ") do |xml|
        svc.to_xml(xml)
      end

      xml_str.should contain(%(<service bom-ref="svc-ref">))
      xml_str.should contain(%(<provider>))
      xml_str.should contain(%(<name>Corp</name>))
      xml_str.should contain(%(<group>com.example</group>))
      xml_str.should contain(%(<name>user-service</name>))
      xml_str.should contain(%(<version>1.0.0</version>))
      xml_str.should contain(%(<description>User management</description>))
      xml_str.should contain(%(<endpoints>))
      xml_str.should contain(%(<endpoint>https://users.example.com</endpoint>))
      xml_str.should contain(%(<authenticated>true</authenticated>))
      xml_str.should contain(%(<x-trust-boundary>true</x-trust-boundary>))
      xml_str.should contain(%(<trustZone>internal</trustZone>))
      xml_str.should contain(%(<data>))
      xml_str.should contain(%(<classification flow="outbound">PII</classification>))
      xml_str.should contain(%(<tags>))
      xml_str.should contain(%(<tag>users</tag>))
    end

    it "handles minimal service" do
      svc = CycloneDX::Service.new(name: "minimal")
      xml_str = XML.build(indent: "  ") do |xml|
        svc.to_xml(xml)
      end

      xml_str.should contain(%(<service>))
      xml_str.should contain(%(<name>minimal</name>))
      xml_str.should_not contain(%(<version>))
      xml_str.should_not contain(%(<endpoints>))
      xml_str.should_not contain(%(<authenticated>))
    end

    it "serializes nested sub-services" do
      sub = CycloneDX::Service.new(name: "sub-service", version: "0.1.0")
      svc = CycloneDX::Service.new(name: "parent", services: [sub])

      xml_str = XML.build(indent: "  ") do |xml|
        svc.to_xml(xml)
      end

      xml_str.should contain(%(<services>))
      xml_str.should contain(%(<name>sub-service</name>))
    end
  end
end
