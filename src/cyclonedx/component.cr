require "json"
require "xml"
require "./models"

# Represents a component in the CycloneDX Bill of Materials (BOM).
# This class is responsible for defining the structure and serialization
# of a software component, including its type, name, version, and PURL.
class CycloneDX::Component
  include JSON::Serializable

  DEFAULT_TYPE    = "library"
  VALID_SCOPES    = ["required", "optional", "excluded"]
  VALID_TYPES     = [
    "application", "framework", "library", "container", "platform",
    "operating-system", "device", "device-driver", "firmware", "file",
    "machine-learning-model", "data", "cryptographic-asset",
  ]

  @[JSON::Field(key: "bom-ref")]
  getter bom_ref : String?
  @[JSON::Field(key: "type")]
  getter component_type : String
  @[JSON::Field(key: "mime-type")]
  getter mime_type : String?
  getter group : String?
  getter name : String
  getter version : String
  getter scope : String?
  getter purl : String?
  getter cpe : String?
  getter description : String?
  getter author : String?
  getter publisher : String?
  getter copyright : String?
  getter supplier : OrganizationalEntity?
  getter manufacturer : OrganizationalEntity?
  getter licenses : Array(License | LicenseExpression)?
  getter hashes : Array(Hash)?
  @[JSON::Field(key: "externalReferences")]
  getter external_references : Array(ExternalReference)?
  getter properties : Array(Property)?
  getter components : Array(Component)?
  getter tags : Array(String)?
  @[JSON::Field(key: "omniborId")]
  getter omnibor_id : Array(String)?
  getter swhid : Array(String)?

  def initialize(@name : String, @version : String, @component_type : String = DEFAULT_TYPE, @purl : String? = nil,
                 @description : String? = nil, @author : String? = nil,
                 @licenses : Array(License | LicenseExpression)? = nil,
                 @external_references : Array(ExternalReference)? = nil, @bom_ref : String? = nil,
                 @scope : String? = nil, @hashes : Array(Hash)? = nil,
                 @properties : Array(Property)? = nil, @group : String? = nil,
                 @copyright : String? = nil, @cpe : String? = nil,
                 @supplier : OrganizationalEntity? = nil, @manufacturer : OrganizationalEntity? = nil,
                 @publisher : String? = nil, @mime_type : String? = nil,
                 @components : Array(Component)? = nil, @tags : Array(String)? = nil,
                 @omnibor_id : Array(String)? = nil, @swhid : Array(String)? = nil)
    if s = @scope
      unless VALID_SCOPES.includes?(s)
        raise ArgumentError.new("Invalid scope '#{s}'. Valid scopes are: #{VALID_SCOPES.join(", ")}")
      end
    end
  end

  def to_xml(xml : XML::Builder) : Nil
    attrs = {"type" => @component_type} of String => String
    if mime = @mime_type
      attrs["mime-type"] = mime
    end
    if bom_ref_val = @bom_ref
      attrs["bom-ref"] = bom_ref_val
    end

    xml.element("component", attributes: attrs) do
      @supplier.try(&.to_xml(xml, "supplier"))
      @manufacturer.try(&.to_xml(xml, "manufacturer"))
      if author = @author
        xml.element("author") { xml.text(author) }
      end
      if publisher = @publisher
        xml.element("publisher") { xml.text(publisher) }
      end
      if group = @group
        xml.element("group") { xml.text(group) }
      end
      xml.element("name") { xml.text(@name) }
      xml.element("version") { xml.text(@version) }
      if description = @description
        xml.element("description") { xml.text(description) }
      end
      if scope_val = @scope
        xml.element("scope") { xml.text(scope_val) }
      end
      if copyright = @copyright
        xml.element("copyright") { xml.text(copyright) }
      end
      @cpe.try { |cpe| xml.element("cpe") { xml.text(cpe) } }

      if hashes_val = @hashes
        xml.element("hashes") do
          hashes_val.each(&.to_xml(xml))
        end
      end

      if licenses_val = @licenses
        xml.element("licenses") do
          licenses_val.each(&.to_xml(xml))
        end
      end

      @purl.try { |purl| xml.element("purl") { xml.text(purl) } }

      if external_refs_val = @external_references
        xml.element("externalReferences") do
          external_refs_val.each(&.to_xml(xml))
        end
      end

      if props = @properties
        xml.element("properties") do
          props.each(&.to_xml(xml))
        end
      end

      if sub_components = @components
        xml.element("components") do
          sub_components.each(&.to_xml(xml))
        end
      end

      if tags_val = @tags
        xml.element("tags") do
          tags_val.each { |tag| xml.element("tag") { xml.text(tag) } }
        end
      end
    end
  end
end
