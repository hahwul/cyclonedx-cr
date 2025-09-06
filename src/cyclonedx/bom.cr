require "json"
require "xml"
require "csv"
require "uuid"
require "./component"

# Represents a CycloneDX Bill of Materials (BOM).
# This class manages a collection of components and provides methods
# for serializing the BOM into different formats (JSON, XML, CSV).
class CycloneDX::BOM
  include JSON::Serializable

  # Specifies the format of the BOM (always "CycloneDX" for JSON serialization).
  @[JSON::Field(key: "bomFormat")]
  property bom_format_json : String = "CycloneDX"
  # The CycloneDX specification version used for JSON serialization.
  @[JSON::Field(key: "specVersion")]
  property spec_version_json : String
  # The version of the BOM itself (not the spec version), typically 1.
  @[JSON::Field(key: "version")]
  property version_json : Int32 = 1
  # An array of `CycloneDX::Component` objects included in the BOM.
  property components : Array(Component)

  @spec_version : String

  # Initializes a new CycloneDX BOM.
  #
  # @param components [Array(Component)] An array of components to include in the BOM.
  # @param spec_version [String] The CycloneDX specification version (e.g., "1.4", "1.5").
  def initialize(@components : Array(Component), spec_version : String)
    @spec_version_json = spec_version
    @spec_version = spec_version
  end

  # Serializes the BOM to XML format.
  # The XML output includes a unique serial number (UUID).
  #
  # @return [String] The BOM in XML format.
  def to_xml
    String.build do |str|
      XML.build(str) do |xml|
        xml.element("bom", attributes: {
          "xmlns":        "http://cyclonedx.org/schema/bom/#{@spec_version}",
          "version":      "1",
          "serialNumber": "urn:uuid:#{UUID.random}",
        }) do
          xml.element("components") do
            @components.each do |comp|
              comp.to_xml(xml)
            end
          end
        end
      end
    end
  end

  # Serializes the BOM to CSV format.
  # The CSV output includes Name, Version, PURL, and Type for each component.
  #
  # @return [String] The BOM in CSV format.
  def to_csv
    CSV.build do |csv|
      csv.row "Name", "Version", "PURL", "Type"
      @components.each do |comp|
        csv.row comp.name, comp.version, comp.purl, comp.component_type
      end
    end
  end
end
