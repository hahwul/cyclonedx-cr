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

    # `evidenceTechnique`. Every value was introduced together with the enum in
    # 1.5, and `evidence/identity` is itself gated to 1.5+, so no value can ever
    # reach a document that does not permit it — this list is for validation
    # only.
    VALID_TECHNIQUES = [
      "source-code-analysis", "binary-analysis", "manifest-analysis",
      "ast-fingerprint", "hash-comparison", "instrumentation",
      "dynamic-analysis", "filename", "attestation", "other",
    ]

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

    # `identityFieldType`. This is the union across all supported spec versions;
    # `omniborId` and `swhid` only exist from 1.6 — see
    # `VersionGate::IDENTITY_FIELD_VERSIONS`. The enum designates no catch-all,
    # so a too-new value cannot be downgraded, only reported.
    VALID_FIELDS = [
      "group", "name", "version", "purl", "cpe", "swid", "hash",
      # 1.6+
      "omniborId", "swhid",
    ]

    getter field : String?
    getter confidence : Float64?
    getter methods : Array(EvidenceMethod)?

    def initialize(@field : String? = nil, @confidence : Float64? = nil,
                   @methods : Array(EvidenceMethod)? = nil)
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
      end
    end
  end

  class EvidenceCopyright
    include JSON::Serializable

    getter text : String

    def initialize(@text : String)
    end

    # A copyright entry is a single `<text>` element; the parent `Evidence`
    # wraps the collection in one `<copyright>` element (copyrightsType allows a
    # single <copyright> containing multiple <text> children).
    def to_xml(xml : XML::Builder)
      xml.element("text") { xml.text @text }
    end
  end

  class Evidence
    include JSON::Serializable

    getter identity : Array(EvidenceIdentity)?
    # `occurrences` is a componentEvidence-level field, NOT a child of
    # `identity` (XSD componentEvidenceType: identity, occurrences, callstack,
    # licenses, copyright).
    getter occurrences : Array(EvidenceOccurrence)?
    @[JSON::Field(converter: CycloneDX::LicenseChoiceConverter)]
    getter licenses : Array(License | LicenseExpression)?
    getter copyright : Array(EvidenceCopyright)?

    def initialize(@identity : Array(EvidenceIdentity)? = nil,
                   @occurrences : Array(EvidenceOccurrence)? = nil,
                   @licenses : Array(License | LicenseExpression)? = nil,
                   @copyright : Array(EvidenceCopyright)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("evidence") do
        if identity_val = @identity
          identity_val.each(&.to_xml(xml))
        end
        if occurrences_val = @occurrences
          xml.element("occurrences") do
            occurrences_val.each(&.to_xml(xml))
          end
        end
        if licenses_val = @licenses
          xml.element("licenses") do
            licenses_val.each(&.to_xml(xml))
          end
        end
        if copyright_val = @copyright
          xml.element("copyright") do
            copyright_val.each(&.to_xml(xml))
          end
        end
      end
    end
  end
end
