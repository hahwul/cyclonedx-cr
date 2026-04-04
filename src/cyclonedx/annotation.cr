require "json"
require "xml"
require "./models"

module CycloneDX
  class Annotator
    include JSON::Serializable

    getter organization : OrganizationalEntity?
    getter individual : OrganizationalContact?

    def initialize(@organization : OrganizationalEntity? = nil, @individual : OrganizationalContact? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("annotator") do
        @organization.try(&.to_xml(xml, "organization"))
        @individual.try { |ind| ind.to_xml(xml, "individual") }
      end
    end
  end

  class Annotation
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter subjects : Array(String)?
    getter annotator : Annotator?
    getter timestamp : String?
    getter text : String?

    def initialize(@subjects : Array(String)? = nil, @annotator : Annotator? = nil,
                   @timestamp : String? = nil, @text : String? = nil,
                   @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end

      xml.element("annotation", attributes: attrs) do
        if subjects_val = @subjects
          xml.element("subjects") do
            subjects_val.each do |ref|
              xml.element("ref") { xml.text ref }
            end
          end
        end
        @annotator.try(&.to_xml(xml))
        if ts = @timestamp
          xml.element("timestamp") { xml.text ts }
        end
        if text = @text
          xml.element("text") { xml.text text }
        end
      end
    end
  end
end
