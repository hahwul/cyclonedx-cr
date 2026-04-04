require "json"
require "xml"
require "./models"

module CycloneDX
  class StandardRequirement
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter identifier : String?
    getter title : String?
    getter text : String?

    def initialize(@identifier : String? = nil, @title : String? = nil,
                   @text : String? = nil, @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      xml.element("requirement", attributes: attrs) do
        if identifier = @identifier
          xml.element("identifier") { xml.text identifier }
        end
        if title = @title
          xml.element("title") { xml.text title }
        end
        if text = @text
          xml.element("text") { xml.text text }
        end
      end
    end
  end

  class Standard
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter name : String?
    getter version : String?
    getter description : String?
    getter owner : String?
    getter requirements : Array(StandardRequirement)?

    def initialize(@name : String? = nil, @version : String? = nil,
                   @description : String? = nil, @owner : String? = nil,
                   @requirements : Array(StandardRequirement)? = nil,
                   @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      xml.element("standard", attributes: attrs) do
        if name = @name
          xml.element("name") { xml.text name }
        end
        if version = @version
          xml.element("version") { xml.text version }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        if owner = @owner
          xml.element("owner") { xml.text owner }
        end
        if reqs = @requirements
          xml.element("requirements") do
            reqs.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class Claim
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter target : String?
    getter predicate : String?
    @[JSON::Field(key: "mitigationStrategies")]
    getter mitigation_strategies : Array(String)?
    getter reasoning : String?
    getter evidence : Array(String)?

    def initialize(@target : String? = nil, @predicate : String? = nil,
                   @mitigation_strategies : Array(String)? = nil,
                   @reasoning : String? = nil, @evidence : Array(String)? = nil,
                   @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      xml.element("claim", attributes: attrs) do
        if target = @target
          xml.element("target") { xml.text target }
        end
        if predicate = @predicate
          xml.element("predicate") { xml.text predicate }
        end
        if reasoning = @reasoning
          xml.element("reasoning") { xml.text reasoning }
        end
        if evidence_val = @evidence
          xml.element("evidence") do
            evidence_val.each { |ref| xml.element("ref") { xml.text ref } }
          end
        end
      end
    end
  end

  class Declarations
    include JSON::Serializable

    getter standards : Array(Standard)?
    getter claims : Array(Claim)?

    def initialize(@standards : Array(Standard)? = nil, @claims : Array(Claim)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("declarations") do
        if standards_val = @standards
          xml.element("standards") do
            standards_val.each(&.to_xml(xml))
          end
        end
        if claims_val = @claims
          xml.element("claims") do
            claims_val.each(&.to_xml(xml))
          end
        end
      end
    end
  end
end
