require "json"
require "xml"
require "./component"
require "./service"
require "./models"

module CycloneDX
  class Metadata
    include JSON::Serializable

    getter timestamp : String?
    getter lifecycles : Array(Lifecycle)?
    getter authors : Array(OrganizationalContact)?
    getter component : Component?
    # 1.6+. Distinct from the older, deprecated `manufacture` below.
    getter manufacturer : OrganizationalEntity?
    getter manufacture : OrganizationalEntity?
    getter supplier : OrganizationalEntity?
    @[JSON::Field(converter: CycloneDX::LicenseChoiceConverter)]
    getter licenses : Array(License | LicenseExpression)?
    getter properties : Array(Property)?

    # `tools` has two mutually exclusive shapes in the schema (an `xs:choice` in
    # XML, a `oneOf` in JSON), so it cannot be a single generated field:
    #
    #   * the original flat list of `toolType` — deprecated from 1.5 but still
    #     valid in every supported version, and what this library emits;
    #   * from 1.5 on, an object of full `components`/`services`, which is what
    #     current third-party producers (syft, trivy, cdxgen, …) write.
    #
    # All three are serialized by hand in `on_to_json`/`to_xml` and parsed in
    # `on_unknown_json_attribute`.
    @[JSON::Field(ignore: true)]
    getter tools : Array(Tool)?
    @[JSON::Field(ignore: true)]
    getter tool_components : Array(Component)?
    @[JSON::Field(ignore: true)]
    getter tool_services : Array(Service)?

    def initialize(@component : Component? = nil, @tools : Array(Tool)? = nil,
                   @authors : Array(OrganizationalContact)? = nil, @timestamp : String? = nil,
                   @properties : Array(Property)? = nil, @lifecycles : Array(Lifecycle)? = nil,
                   @manufacture : OrganizationalEntity? = nil, @supplier : OrganizationalEntity? = nil,
                   @manufacturer : OrganizationalEntity? = nil,
                   @licenses : Array(License | LicenseExpression)? = nil,
                   @tool_components : Array(Component)? = nil,
                   @tool_services : Array(Service)? = nil)
    end

    # True when the 1.5+ object form of `tools` is populated.
    private def tools_as_object? : Bool
      !@tool_components.nil? || !@tool_services.nil?
    end

    protected def on_to_json(json : JSON::Builder) : Nil
      if tools_as_object?
        json.field "tools" do
          json.object do
            @tool_components.try { |c| json.field("components") { c.to_json(json) } }
            @tool_services.try { |s| json.field("services") { s.to_json(json) } }
          end
        end
      elsif legacy = @tools
        json.field("tools") { legacy.to_json(json) }
      end
    end

    protected def on_unknown_json_attribute(pull : JSON::PullParser, key, key_location) : Nil
      return pull.skip unless key == "tools"

      case pull.kind
      when .begin_array?
        @tools = Array(Tool).new(pull)
      when .begin_object?
        pull.read_object do |field|
          case field
          when "components" then @tool_components = Array(Component).new(pull)
          when "services"   then @tool_services = Array(Service).new(pull)
          else                   pull.skip
          end
        end
      else
        pull.skip
      end
    end

    def to_xml(xml : XML::Builder)
      # Element order follows the CycloneDX metadataType XSD <sequence>:
      # timestamp, lifecycles, tools, authors, component, manufacturer,
      # manufacture, supplier, licenses, properties.
      xml.element("metadata") do
        if ts = @timestamp
          xml.element("timestamp") { xml.text ts }
        end
        if lifecycles_val = @lifecycles
          xml.element("lifecycles") do
            lifecycles_val.each(&.to_xml(xml))
          end
        end
        tools_to_xml(xml)
        if authors_val = @authors
          xml.element("authors") do
            authors_val.each(&.to_xml(xml))
          end
        end
        @component.try(&.to_xml(xml))
        @manufacturer.try(&.to_xml(xml, "manufacturer"))
        @manufacture.try(&.to_xml(xml, "manufacture"))
        @supplier.try(&.to_xml(xml, "supplier"))

        if licenses_val = @licenses
          xml.element("licenses") do
            licenses_val.each(&.to_xml(xml))
          end
        end

        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end

    # The two shapes are an `xs:choice`, so exactly one may be emitted.
    private def tools_to_xml(xml : XML::Builder) : Nil
      if tools_as_object?
        xml.element("tools") do
          @tool_components.try do |comps|
            xml.element("components") { comps.each(&.to_xml(xml)) }
          end
          @tool_services.try do |svcs|
            xml.element("services") { svcs.each(&.to_xml(xml)) }
          end
        end
      elsif legacy = @tools
        xml.element("tools") { legacy.each(&.to_xml(xml)) }
      end
    end
  end
end
