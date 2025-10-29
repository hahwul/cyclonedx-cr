require "json"
require "xml"

# Represents a component in the CycloneDX Bill of Materials (BOM).
# This class is responsible for defining the structure and serialization
# of a software component, including its type, name, version, and PURL.
class CycloneDX::Component
  include JSON::Serializable

  # The type of the component (e.g., "library", "application").
  @[JSON::Field(key: "type")]
  property component_type : String
  # The name of the component.
  property name : String
  # The version of the component.
  property version : String
  # The Package URL (PURL) of the component, if available.
  property purl : String?

  # Initializes a new CycloneDX Component.
  #
  # @param name [String] The name of the component.
  # @param version [String] The version of the component.
  # @param component_type [String] The type of the component (default: "library").
  # @param purl [String?] The PURL of the component (default: nil).
  def initialize(@name : String, @version : String, @component_type = "library", @purl = nil)
  end

  # Serializes the component to XML format.
  #
  # @param builder [XML::Builder] The XML builder instance.
  def to_xml(builder : XML::Builder)
    builder.element("component", attributes: {"type": @component_type}) do
      builder.element("name") { builder.text(@name) }
      builder.element("version") { builder.text(@version) }
      builder.element("purl") { builder.text(@purl.not_nil!) } if @purl
    end
  end
end
