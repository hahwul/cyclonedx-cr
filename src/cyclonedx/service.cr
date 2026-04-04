require "json"
require "xml"
require "./models"

module CycloneDX
  class DataClassification
    include JSON::Serializable

    getter flow : String
    getter classification : String

    def initialize(@flow : String, @classification : String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("classification", attributes: {"flow" => @flow}) do
        xml.text @classification
      end
    end
  end

  class Service
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter provider : OrganizationalEntity?
    getter group : String?
    getter name : String
    getter version : String?
    getter description : String?
    getter endpoints : Array(String)?
    getter authenticated : Bool?
    @[JSON::Field(key: "x-trust-boundary")]
    getter x_trust_boundary : Bool?
    @[JSON::Field(key: "trustZone")]
    getter trust_zone : String?
    getter data : Array(DataClassification)?
    getter licenses : Array(License | LicenseExpression)?
    @[JSON::Field(key: "externalReferences")]
    getter external_references : Array(ExternalReference)?
    getter properties : Array(Property)?
    getter services : Array(Service)?
    getter tags : Array(String)?

    def initialize(@name : String, @version : String? = nil, @bom_ref : String? = nil,
                   @provider : OrganizationalEntity? = nil, @group : String? = nil,
                   @description : String? = nil, @endpoints : Array(String)? = nil,
                   @authenticated : Bool? = nil, @x_trust_boundary : Bool? = nil,
                   @trust_zone : String? = nil, @data : Array(DataClassification)? = nil,
                   @licenses : Array(License | LicenseExpression)? = nil,
                   @external_references : Array(ExternalReference)? = nil,
                   @properties : Array(Property)? = nil, @services : Array(Service)? = nil,
                   @tags : Array(String)? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end

      xml.element("service", attributes: attrs) do
        @provider.try(&.to_xml(xml, "provider"))
        if group = @group
          xml.element("group") { xml.text group }
        end
        xml.element("name") { xml.text @name }
        if version = @version
          xml.element("version") { xml.text version }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        if endpoints_val = @endpoints
          xml.element("endpoints") do
            endpoints_val.each do |ep|
              xml.element("endpoint") { xml.text ep }
            end
          end
        end
        if auth = @authenticated
          xml.element("authenticated") { xml.text auth.to_s }
        end
        if xtb = @x_trust_boundary
          xml.element("x-trust-boundary") { xml.text xtb.to_s }
        end
        if tz = @trust_zone
          xml.element("trustZone") { xml.text tz }
        end
        if data_val = @data
          xml.element("data") do
            data_val.each(&.to_xml(xml))
          end
        end
        if licenses_val = @licenses
          xml.element("licenses") do
            licenses_val.each(&.to_xml(xml))
          end
        end
        if external_refs_val = @external_references
          xml.element("externalReferences") do
            external_refs_val.each(&.to_xml(xml))
          end
        end
        if sub_services = @services
          xml.element("services") do
            sub_services.each(&.to_xml(xml))
          end
        end
        if tags_val = @tags
          xml.element("tags") do
            tags_val.each { |tag| xml.element("tag") { xml.text(tag) } }
          end
        end
        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end
end
