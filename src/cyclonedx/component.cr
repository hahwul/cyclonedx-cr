require "json"
require "xml"

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

  # Initializes a new CycloneDX Component.
  #
  # @param name [String] The name of the component.
  # @param version [String] The version of the component.
  # @param component_type [String] The type of the component (default: "library").
  # @param purl [String?] The PURL of the component (default: nil).
  def initialize(@name : String, @version : String, @component_type : String = DEFAULT_TYPE, @purl : String? = nil)
  end

  # Serializes the component to XML format.
  #
  # @param builder [XML::Builder] The XML builder instance.
  def to_xml(builder : XML::Builder) : Nil
    builder.element("component", attributes: {"type": @component_type}) do
      builder.element("name") { builder.text(@name) }
      builder.element("version") { builder.text(@version) }
      @purl.try { |purl| builder.element("purl") { builder.text(purl) } }
    end
  end
end
