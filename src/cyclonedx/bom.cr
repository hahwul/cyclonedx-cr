require "json"
require "xml"
require "csv"
require "uuid"
require "./component"
require "./metadata"

# Represents a CycloneDX Bill of Materials (BOM).
# This class manages a collection of components and provides methods
# for serializing the BOM into different formats (JSON, XML, CSV).
class CycloneDX::BOM
  include JSON::Serializable

  BOM_FORMAT    = "CycloneDX"
  BOM_VERSION   = 1
  XML_NAMESPACE = "http://cyclonedx.org/schema/bom"

  # Specifies the format of the BOM (always "CycloneDX" for JSON serialization).
  @[JSON::Field(key: "bomFormat")]
  getter bom_format : String = BOM_FORMAT

  # The CycloneDX specification version.
  @[JSON::Field(key: "specVersion")]
  getter spec_version : String

  # The version of the BOM itself (not the spec version), typically 1.
  @[JSON::Field(key: "version")]
  getter bom_version : Int32 = BOM_VERSION

  # Metadata about the BOM.
  getter metadata : Metadata?

  # An array of `CycloneDX::Component` objects included in the BOM.
  getter components : Array(Component)

  # Initializes a new CycloneDX BOM.
  #
  # @param components [Array(Component)] An array of components to include in the BOM.
  # @param spec_version [String] The CycloneDX specification version (e.g., "1.4", "1.5").
  # @param metadata [Metadata?] The metadata for the BOM.
  def initialize(@components : Array(Component), @spec_version : String, @metadata : Metadata? = nil)
  end

  # Serializes the BOM to XML format.
  # The XML output includes a unique serial number (UUID).
  #
  # @return [String] The BOM in XML format.
  def to_xml : String
    String.build do |str|
      XML.build(str) do |xml|
        xml.element("bom", attributes: {
          "xmlns":        "#{XML_NAMESPACE}/#{@spec_version}",
          "version":      BOM_VERSION.to_s,
          "serialNumber": "urn:uuid:#{UUID.random}",
        }) do
          @metadata.try(&.to_xml(xml))
          xml.element("components") do
            @components.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  # Serializes the BOM to CSV format.
  # The CSV output includes Name, Version, PURL, and Type for each component.
  #
  # @return [String] The BOM in CSV format.
  def to_csv : String
    CSV.build do |csv|
      csv.row "Name", "Version", "PURL", "Type"
      @components.each do |component|
        csv.row component.name, component.version, component.purl, component.component_type
      end
    end
  end
end
