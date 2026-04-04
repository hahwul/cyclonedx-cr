require "json"
require "xml"

module CycloneDX
  class Composition
    include JSON::Serializable

    VALID_AGGREGATES = [
      "complete", "incomplete", "unknown", "not_specified",
      "incomplete_first_party_only", "incomplete_first_party_proprietary_only",
      "incomplete_first_party_opensource_only", "incomplete_third_party_only",
      "incomplete_third_party_proprietary_only", "incomplete_third_party_opensource_only",
    ]

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter aggregate : String
    getter assemblies : Array(String)?
    getter dependencies : Array(String)?
    getter vulnerabilities : Array(String)?

    def initialize(@aggregate : String, @bom_ref : String? = nil,
                   @assemblies : Array(String)? = nil, @dependencies : Array(String)? = nil,
                   @vulnerabilities : Array(String)? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end

      xml.element("composition", attributes: attrs) do
        xml.element("aggregate") { xml.text @aggregate }
        if assemblies_val = @assemblies
          xml.element("assemblies") do
            assemblies_val.each do |ref|
              xml.element("assembly", attributes: {"ref" => ref})
            end
          end
        end
        if deps = @dependencies
          xml.element("dependencies") do
            deps.each do |ref|
              xml.element("dependency", attributes: {"ref" => ref})
            end
          end
        end
        if vulns = @vulnerabilities
          xml.element("vulnerabilities") do
            vulns.each do |ref|
              xml.element("vulnerability", attributes: {"ref" => ref})
            end
          end
        end
      end
    end
  end
end
