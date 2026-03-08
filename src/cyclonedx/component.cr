require "json"
require "xml"
require "./models"

# Represents a component in the CycloneDX Bill of Materials (BOM).
# This class is responsible for defining the structure and serialization
# of a software component, including its type, name, version, and PURL.
class CycloneDX::Component
  include JSON::Serializable

  DEFAULT_TYPE = "library"

  # A unique identifier for the component, used in dependency references.
  @[JSON::Field(key: "bom-ref")]
  getter bom_ref : String?
  # The type of the component (e.g., "library", "application").
  @[JSON::Field(key: "type")]
  getter component_type : String
  # The name of the component.
  getter name : String
  # The version of the component.
  getter version : String
  # The scope of the component (e.g., "required", "optional", "excluded").
  getter scope : String?
  # The Package URL (PURL) of the component, if available.
  getter purl : String?

  getter description : String?
  getter author : String?
  getter licenses : Array(License)?
  getter hashes : Array(Hash)?
  @[JSON::Field(key: "externalReferences")]
  getter external_references : Array(ExternalReference)?

  # Initializes a new CycloneDX Component.
  def initialize(@name : String, @version : String, @component_type : String = DEFAULT_TYPE, @purl : String? = nil,
                 @description : String? = nil, @author : String? = nil, @licenses : Array(License)? = nil,
                 @external_references : Array(ExternalReference)? = nil, @bom_ref : String? = nil,
                 @scope : String? = nil, @hashes : Array(Hash)? = nil)
  end

  # Serializes the component to XML format.
  def to_xml(xml : XML::Builder) : Nil
    attrs = {"type" => @component_type} of String => String
    if bom_ref_val = @bom_ref
      attrs["bom-ref"] = bom_ref_val
    end

    xml.element("component", attributes: attrs) do
      if author = @author
        xml.element("author") { xml.text(author) }
      end
      xml.element("name") { xml.text(@name) }
      xml.element("version") { xml.text(@version) }
      if description = @description
        xml.element("description") { xml.text(description) }
      end
      if scope_val = @scope
        xml.element("scope") { xml.text(scope_val) }
      end

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
    end
  end
end
