require "json"
require "xml"
require "./models"

# Represents a component in the CycloneDX Bill of Materials (BOM).
# This class is responsible for defining the structure and serialization
# of a software component, including its type, name, version, and PURL.
class CycloneDX::Component
  include JSON::Serializable

  DEFAULT_TYPE = "library"

  # The type of the component (e.g., "library", "application").
  @[JSON::Field(key: "type")]
  getter component_type : String
  # The name of the component.
  getter name : String
  # The version of the component.
  getter version : String
  # The Package URL (PURL) of the component, if available.
  getter purl : String?

  getter description : String?
  getter author : String?
  getter licenses : Array(License)?
  @[JSON::Field(key: "externalReferences")]
  getter external_references : Array(ExternalReference)?

  # Initializes a new CycloneDX Component.
  #
  # @param name [String] The name of the component.
  # @param version [String] The version of the component.
  # @param component_type [String] The type of the component (default: "library").
  # @param purl [String?] The PURL of the component (default: nil).
  # @param description [String?] The description of the component.
  # @param author [String?] The author of the component.
  # @param licenses [Array(License)?] The licenses of the component.
  # @param external_references [Array(ExternalReference)?] The external references of the component.
  def initialize(@name : String, @version : String, @component_type : String = DEFAULT_TYPE, @purl : String? = nil,
                 @description : String? = nil, @author : String? = nil, @licenses : Array(License)? = nil, @external_references : Array(ExternalReference)? = nil)
  end

  # Serializes the component to XML format.
  #
  # @param builder [XML::Builder] The XML builder instance.
  def to_xml(builder : XML::Builder) : Nil
    builder.element("component", attributes: {"type": @component_type}) do
      if author = @author
        builder.element("author") { builder.text(author) }
      end
      builder.element("name") { builder.text(@name) }
      builder.element("version") { builder.text(@version) }
      if description = @description
        builder.element("description") { builder.text(description) }
      end

      if licenses_val = @licenses
        builder.element("licenses") do
          licenses_val.each(&.to_xml(builder))
        end
      end

      @purl.try { |purl| builder.element("purl") { builder.text(purl) } }

      if external_refs_val = @external_references
        builder.element("externalReferences") do
          external_refs_val.each(&.to_xml(builder))
        end
      end
    end
  end
end
