require "json"
require "xml"
require "./models"

module CycloneDX
  class EvidenceOccurrence
    include JSON::Serializable

    getter location : String

    def initialize(@location : String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("occurrence") do
        xml.element("location") { xml.text @location }
      end
    end
  end

  class EvidenceMethod
    include JSON::Serializable

    getter technique : String
    getter confidence : Float64?

    def initialize(@technique : String, @confidence : Float64? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("method") do
        xml.element("technique") { xml.text @technique }
        if conf = @confidence
          xml.element("confidence") { xml.text conf.to_s }
        end
      end
    end
  end

  class EvidenceIdentity
    include JSON::Serializable

    getter field : String?
    getter confidence : Float64?
    getter methods : Array(EvidenceMethod)?
    getter occurrences : Array(EvidenceOccurrence)?

    def initialize(@field : String? = nil, @confidence : Float64? = nil,
                   @methods : Array(EvidenceMethod)? = nil,
                   @occurrences : Array(EvidenceOccurrence)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("identity") do
        if field = @field
          xml.element("field") { xml.text field }
        end
        if confidence = @confidence
          xml.element("confidence") { xml.text confidence.to_s }
        end
        if methods_val = @methods
          xml.element("methods") do
            methods_val.each(&.to_xml(xml))
          end
        end
        if occurrences_val = @occurrences
          xml.element("occurrences") do
            occurrences_val.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class EvidenceCopyright
    include JSON::Serializable

    getter text : String

    def initialize(@text : String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("copyright") do
        xml.element("text") { xml.text @text }
      end
    end
  end

  class Evidence
    include JSON::Serializable

    getter identity : Array(EvidenceIdentity)?
    getter licenses : Array(License | LicenseExpression)?
    getter copyright : Array(EvidenceCopyright)?

    def initialize(@identity : Array(EvidenceIdentity)? = nil,
                   @licenses : Array(License | LicenseExpression)? = nil,
                   @copyright : Array(EvidenceCopyright)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("evidence") do
        if identity_val = @identity
          identity_val.each(&.to_xml(xml))
        end
        if licenses_val = @licenses
          xml.element("licenses") do
            licenses_val.each(&.to_xml(xml))
          end
        end
        if copyright_val = @copyright
          copyright_val.each(&.to_xml(xml))
        end
      end
    end
  end
end
