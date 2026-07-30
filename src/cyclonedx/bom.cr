require "json"
require "xml"
require "csv"
require "uuid"
require "./component"
require "./metadata"
require "./models"
require "./vulnerability"
require "./service"
require "./composition"
require "./annotation"
require "./formulation"
require "./declaration"
require "./version_gate"

# Represents a CycloneDX Bill of Materials (BOM).
# This class manages a collection of components and provides methods
# for serializing the BOM into different formats (JSON, XML, CSV).
class CycloneDX::BOM
  include JSON::Serializable

  BOM_FORMAT    = "CycloneDX"
  BOM_VERSION   = 1
  XML_NAMESPACE = "http://cyclonedx.org/schema/bom"
  JSON_SCHEMA   = "http://cyclonedx.org/schema/bom"

  # Specifies the format of the BOM (always "CycloneDX" for JSON serialization).
  @[JSON::Field(key: "bomFormat")]
  getter bom_format : String = BOM_FORMAT

  # The CycloneDX specification version.
  @[JSON::Field(key: "specVersion")]
  getter spec_version : String

  # The version of the BOM itself (not the spec version), typically 1.
  @[JSON::Field(key: "version")]
  getter bom_version : Int32 = BOM_VERSION

  # The unique serial number of the BOM. Randomly generated unless the caller
  # supplies one; a caller-supplied value is what makes byte-reproducible output
  # possible (see the CLI's `--reproducible`).
  @[JSON::Field(key: "serialNumber")]
  getter serial_number : String

  # Metadata about the BOM.
  getter metadata : Metadata?

  # An array of `CycloneDX::Component` objects included in the BOM.
  #
  # `components` is optional in every CycloneDX version, so it defaults to empty
  # rather than being required on parse — a BOM that inventories only services,
  # or that carries nothing but vulnerabilities, legitimately omits it.
  getter components : Array(Component) = [] of Component

  # An array of `CycloneDX::Dependency` objects describing component relationships.
  getter dependencies : Array(Dependency)?

  # An array of `CycloneDX::Property` objects for extensibility.
  getter properties : Array(Property)?

  # An array of `CycloneDX::Vulnerability` objects for VDR/VEX.
  getter vulnerabilities : Array(Vulnerability)?

  # An array of `CycloneDX::Service` objects for SaaSBOM.
  getter services : Array(Service)?

  # An array of `CycloneDX::Composition` objects for completeness assertions.
  getter compositions : Array(Composition)?
  getter annotations : Array(Annotation)?
  getter formulation : Array(Formula)?
  getter declarations : Declarations?

  # An array of `CycloneDX::ExternalReference` objects for the BOM itself.
  @[JSON::Field(key: "externalReferences")]
  getter external_references : Array(ExternalReference)?

  # Definitions for standards (1.5+).
  getter definitions : Definitions?

  SUPPORTED_VERSIONS = ["1.4", "1.5", "1.6", "1.7"]

  # Set while `#raw_json` is collecting the pre-gate document so that
  # `#to_json(JSON::Builder)` hands straight through to the generated
  # serializer instead of recursing into the gate. Not serialized, and not safe
  # to serialize the same BOM instance from two fibers at once.
  @[JSON::Field(ignore: true)]
  @ungated = false

  # Initializes a new CycloneDX BOM.
  def initialize(@components : Array(Component), @spec_version : String,
                 @metadata : Metadata? = nil, @dependencies : Array(Dependency)? = nil,
                 @properties : Array(Property)? = nil, @vulnerabilities : Array(Vulnerability)? = nil,
                 @services : Array(Service)? = nil, @compositions : Array(Composition)? = nil,
                 @annotations : Array(Annotation)? = nil, @formulation : Array(Formula)? = nil,
                 @declarations : Declarations? = nil, @external_references : Array(ExternalReference)? = nil,
                 @definitions : Definitions? = nil, serial_number : String? = nil)
    unless SUPPORTED_VERSIONS.includes?(@spec_version)
      raise ArgumentError.new("Unsupported spec version '#{@spec_version}'. Supported versions are: #{SUPPORTED_VERSIONS.join(", ")}")
    end
    @serial_number = serial_number || "urn:uuid:#{UUID.random}"
  end

  # The `$schema` value for the declared spec version. The 1.4 and 1.5 JSON
  # schemas constrain this key to one exact URL, so it is always derived rather
  # than caller-supplied. XML carries the same information in `xmlns`.
  def schema_url : String
    "#{JSON_SCHEMA}-#{@spec_version}.schema.json"
  end

  # Serializes the BOM to JSON.
  #
  # The object model may carry fields newer than the declared `specVersion`
  # (e.g. a 1.4 BOM that was handed `lifecycles`). To keep the output
  # schema-valid, the raw serialization is filtered through `VersionGate`,
  # which strips or downgrades anything newer than `@spec_version`.
  #
  # This overrides the `JSON::Serializable` implementation rather than wrapping
  # only the no-arg `to_json`, because every other JSON entry point in stdlib
  # (`to_pretty_json`, `to_json(IO)`, and serialization as part of a larger
  # document) funnels through this method. Gating only the no-arg form left all
  # of those emitting ungated output.
  def to_json(json : JSON::Builder) : Nil
    return super(json) if @ungated
    with_schema_url(VersionGate.filter_json_any(raw_json, @spec_version)).to_json(json)
  end

  # Prepends the `$schema` key to a filtered document.
  #
  # `$schema` is injected here rather than being an instance variable so that
  # reading a BOM back with `from_json` neither requires the key nor carries a
  # stale value forward: it is always recomputed from `spec_version`. Building a
  # fresh hash also puts it first, which is where every CycloneDX example has it.
  private def with_schema_url(doc : JSON::Any) : JSON::Any
    obj = doc.as_h?
    return doc unless obj
    merged = {"$schema" => JSON::Any.new(schema_url)}
    obj.each { |key, value| merged[key] = value unless key == "$schema" }
    JSON::Any.new(merged)
  end

  # The document as `JSON::Serializable` produces it, *before* spec-version
  # gating.
  #
  # `Validator` diffs this against the gated document to find fields that are
  # newer than the declared `specVersion`, so the rules for what gets stripped
  # live only in `VersionGate` and cannot drift out of sync with the validator.
  # The two documents therefore differ in exactly the places the gate edited.
  def raw_json : String
    @ungated = true
    String.build do |str|
      JSON.build(str) { |json| to_json(json) }
    end
  ensure
    @ungated = false
  end

  # Serializes the BOM to XML format.
  def to_xml : String
    raw = build_xml
    VersionGate.filter_xml(raw, @spec_version)
  end

  # Builds the raw (unfiltered) XML for the BOM.
  private def build_xml : String
    String.build do |str|
      XML.build(str) do |xml|
        xml.element("bom", attributes: {
          "xmlns":        "#{XML_NAMESPACE}/#{@spec_version}",
          "version":      BOM_VERSION.to_s,
          "serialNumber": @serial_number,
        }) do
          # Element order below follows the CycloneDX bomType XSD <sequence>:
          # metadata, components, services, externalReferences, dependencies,
          # compositions, properties, vulnerabilities, annotations, formulation,
          # declarations, definitions. Emitting out of this order fails XSD
          # validation when the corresponding fields are populated.
          @metadata.try(&.to_xml(xml))
          xml.element("components") do
            @components.each(&.to_xml(xml))
          end
          if svcs = @services
            xml.element("services") do
              svcs.each(&.to_xml(xml))
            end
          end
          if ext_refs = @external_references
            xml.element("externalReferences") do
              ext_refs.each(&.to_xml(xml))
            end
          end
          if deps = @dependencies
            xml.element("dependencies") do
              deps.each(&.to_xml(xml))
            end
          end
          if comps = @compositions
            xml.element("compositions") do
              comps.each(&.to_xml(xml))
            end
          end
          if props = @properties
            xml.element("properties") do
              props.each(&.to_xml(xml))
            end
          end
          if vulns = @vulnerabilities
            xml.element("vulnerabilities") do
              vulns.each(&.to_xml(xml))
            end
          end
          if annotations_val = @annotations
            xml.element("annotations") do
              annotations_val.each(&.to_xml(xml))
            end
          end
          if formulation_val = @formulation
            xml.element("formulation") do
              formulation_val.each(&.to_xml(xml))
            end
          end
          @declarations.try(&.to_xml(xml))
          @definitions.try(&.to_xml(xml))
        end
      end
    end
  end

  # Characters that make a spreadsheet treat a cell as a formula rather than as
  # text. Excel, LibreOffice and Google Sheets all evaluate such cells on open.
  CSV_FORMULA_PREFIXES = {'=', '+', '-', '@'}

  # Serializes the BOM to CSV format.
  #
  # The root component lives in `metadata.component` (not in `components`), so it
  # is emitted as the first row to keep the CSV consistent with the JSON/XML
  # output, which both represent the root component.
  #
  # `Scope` and `BOM-Ref` are appended after the original four columns so a
  # consumer reading by column index is unaffected.
  def to_csv : String
    CSV.build do |csv|
      csv.row "Name", "Version", "PURL", "Type", "Scope", "BOM-Ref"
      if root = @metadata.try(&.component)
        csv_row(csv, root)
      end
      @components.each do |component|
        csv_row(csv, component)
      end
    end
  end

  private def csv_row(csv : CSV::Builder, component : Component) : Nil
    csv.row csv_safe(component.name), csv_safe(component.version), csv_safe(component.purl),
      csv_safe(component.component_type), csv_safe(component.scope), csv_safe(component.bom_ref)
  end

  # Neutralises spreadsheet formula injection. Component names and versions are
  # copied verbatim out of `shard.yml`/`shard.lock`, so a name like
  # `=cmd|'/C calc'!A0` would otherwise be evaluated as a formula when the
  # export is opened. Prefixing with a single quote is the standard mitigation:
  # the spreadsheet renders the cell as literal text and the quote is not part
  # of the value. Only the CSV serializer needs this — JSON and XML consumers do
  # not evaluate cell contents.
  private def csv_safe(value : String?) : String?
    return value if value.nil? || value.empty?
    CSV_FORMULA_PREFIXES.includes?(value[0]) ? "'#{value}" : value
  end
end
