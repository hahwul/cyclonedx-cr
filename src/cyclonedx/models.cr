require "json"
require "xml"

module CycloneDX
  class AttachedText
    include JSON::Serializable

    getter content : String
    @[JSON::Field(key: "contentType")]
    getter content_type : String?
    getter encoding : String?

    def initialize(@content : String, @content_type : String? = nil, @encoding : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if ct = @content_type
        attrs["content-type"] = ct
      end
      if enc = @encoding
        attrs["encoding"] = enc
      end
      xml.element("text", attributes: attrs) do
        xml.text @content
      end
    end
  end

  class License
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter id : String?
    getter name : String?
    getter url : String?
    getter text : AttachedText?
    getter acknowledgement : String?

    def initialize(@id : String? = nil, @name : String? = nil, @url : String? = nil,
                   @bom_ref : String? = nil, @text : AttachedText? = nil,
                   @acknowledgement : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      if ack = @acknowledgement
        attrs["acknowledgement"] = ack
      end

      xml.element("license", attributes: attrs) do
        if id_val = @id
          xml.element("id") { xml.text id_val }
        elsif name_val = @name
          xml.element("name") { xml.text name_val }
        end
        if url_val = @url
          xml.element("url") { xml.text url_val }
        end
        @text.try(&.to_xml(xml))
      end
    end
  end

  class LicenseExpression
    include JSON::Serializable

    getter expression : String
    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter acknowledgement : String?

    def initialize(@expression : String, @bom_ref : String? = nil, @acknowledgement : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      if ack = @acknowledgement
        attrs["acknowledgement"] = ack
      end
      if attrs.empty?
        xml.element("expression") { xml.text @expression }
      else
        xml.element("expression", attributes: attrs) { xml.text @expression }
      end
    end
  end

  class Hash
    include JSON::Serializable

    @[JSON::Field(key: "alg")]
    getter algorithm : String
    getter content : String

    def initialize(@algorithm : String, @content : String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("hash", attributes: {"alg" => @algorithm}) do
        xml.text @content
      end
    end
  end

  class ExternalReference
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter ref_type : String
    getter url : String
    getter comment : String?
    getter hashes : Array(Hash)?

    def initialize(@ref_type : String, @url : String, @comment : String? = nil, @hashes : Array(Hash)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("reference", attributes: {"type" => @ref_type}) do
        xml.element("url") { xml.text @url }
        if comment_val = @comment
          xml.element("comment") { xml.text comment_val }
        end
        if hashes_val = @hashes
          xml.element("hashes") do
            hashes_val.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class Dependency
    include JSON::Serializable

    getter ref : String
    @[JSON::Field(key: "dependsOn")]
    getter depends_on : Array(String)?
    getter provides : Array(String)?

    def initialize(@ref : String, @depends_on : Array(String)? = nil,
                   @provides : Array(String)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("dependency", attributes: {"ref" => @ref}) do
        if deps = @depends_on
          deps.each do |dep_ref|
            xml.element("dependency", attributes: {"ref" => dep_ref})
          end
        end
        if provides_val = @provides
          provides_val.each do |prov_ref|
            xml.element("provides", attributes: {"ref" => prov_ref})
          end
        end
      end
    end
  end

  class Tool
    include JSON::Serializable

    getter vendor : String?
    getter name : String?
    getter version : String?

    def initialize(@vendor : String? = nil, @name : String? = nil, @version : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("tool") do
        if vendor = @vendor
          xml.element("vendor") { xml.text vendor }
        end
        if name = @name
          xml.element("name") { xml.text name }
        end
        if version = @version
          xml.element("version") { xml.text version }
        end
      end
    end
  end

  class OrganizationalContact
    include JSON::Serializable

    getter name : String?
    getter email : String?
    getter phone : String?

    def initialize(@name : String? = nil, @email : String? = nil, @phone : String? = nil)
    end

    def to_xml(xml : XML::Builder, element_name : String = "author")
      xml.element(element_name) do
        if name = @name
          xml.element("name") { xml.text name }
        end
        if email = @email
          xml.element("email") { xml.text email }
        end
        if phone = @phone
          xml.element("phone") { xml.text phone }
        end
      end
    end
  end

  class Lifecycle
    include JSON::Serializable

    VALID_PHASES = [
      "design", "pre-build", "build", "post-build",
      "operations", "discovery", "decommission",
    ]

    getter phase : String?
    getter name : String?
    getter description : String?

    def initialize(@phase : String? = nil, @name : String? = nil, @description : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("lifecycle") do
        if phase = @phase
          xml.element("phase") { xml.text phase }
        end
        if name = @name
          xml.element("name") { xml.text name }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
      end
    end
  end

  class OrganizationalEntity
    include JSON::Serializable

    getter name : String?
    getter url : Array(String)?
    getter contact : Array(OrganizationalContact)?

    def initialize(@name : String? = nil, @url : Array(String)? = nil, @contact : Array(OrganizationalContact)? = nil)
    end

    def to_xml(xml : XML::Builder, element_name : String = "organizationalEntity")
      xml.element(element_name) do
        if name = @name
          xml.element("name") { xml.text name }
        end
        if urls = @url
          urls.each do |u|
            xml.element("url") { xml.text u }
          end
        end
        if contacts = @contact
          contacts.each { |c| c.to_xml(xml, "contact") }
        end
      end
    end
  end

  class Property
    include JSON::Serializable

    getter name : String
    getter value : String?

    def initialize(@name : String, @value : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("property", attributes: {"name" => @name}) do
        if v = @value
          xml.text v
        end
      end
    end
  end

  class Definitions
    include JSON::Serializable

    getter standards : Array(DefinitionStandard)?

    def initialize(@standards : Array(DefinitionStandard)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("definitions") do
        if standards_val = @standards
          xml.element("standards") do
            standards_val.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class DefinitionStandard
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter name : String?
    getter version : String?
    getter description : String?
    getter owner : String?
    getter requirements : Array(DefinitionRequirement)?
    @[JSON::Field(key: "externalReferences")]
    getter external_references : Array(ExternalReference)?

    def initialize(@name : String? = nil, @version : String? = nil,
                   @description : String? = nil, @owner : String? = nil,
                   @requirements : Array(DefinitionRequirement)? = nil,
                   @external_references : Array(ExternalReference)? = nil,
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
        if ext_refs = @external_references
          xml.element("externalReferences") do
            ext_refs.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class DefinitionRequirement
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    getter identifier : String?
    getter title : String?
    getter text : String?
    getter descriptions : Array(String)?
    @[JSON::Field(key: "externalReferences")]
    getter external_references : Array(ExternalReference)?

    def initialize(@identifier : String? = nil, @title : String? = nil,
                   @text : String? = nil, @descriptions : Array(String)? = nil,
                   @external_references : Array(ExternalReference)? = nil,
                   @bom_ref : String? = nil)
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
        if descs = @descriptions
          xml.element("descriptions") do
            descs.each { |d| xml.element("description") { xml.text d } }
          end
        end
        if ext_refs = @external_references
          xml.element("externalReferences") do
            ext_refs.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class ReleaseNotes
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter release_type : String?
    getter title : String?
    @[JSON::Field(key: "featuredImage")]
    getter featured_image : String?
    @[JSON::Field(key: "socialImage")]
    getter social_image : String?
    getter description : String?
    getter timestamp : String?
    getter aliases : Array(String)?
    getter tags : Array(String)?
    getter resolves : Array(Issue)?
    getter notes : Array(Note)?
    getter properties : Array(Property)?

    def initialize(@release_type : String? = nil, @title : String? = nil,
                   @featured_image : String? = nil, @social_image : String? = nil,
                   @description : String? = nil, @timestamp : String? = nil,
                   @aliases : Array(String)? = nil, @tags : Array(String)? = nil,
                   @resolves : Array(Issue)? = nil, @notes : Array(Note)? = nil,
                   @properties : Array(Property)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("releaseNotes") do
        if rt = @release_type
          xml.element("type") { xml.text rt }
        end
        if title = @title
          xml.element("title") { xml.text title }
        end
        if fi = @featured_image
          xml.element("featuredImage") { xml.text fi }
        end
        if si = @social_image
          xml.element("socialImage") { xml.text si }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        if ts = @timestamp
          xml.element("timestamp") { xml.text ts }
        end
        if aliases_val = @aliases
          xml.element("aliases") do
            aliases_val.each { |a| xml.element("alias") { xml.text a } }
          end
        end
        if tags_val = @tags
          xml.element("tags") do
            tags_val.each { |t| xml.element("tag") { xml.text t } }
          end
        end
        if resolves_val = @resolves
          xml.element("resolves") do
            resolves_val.each(&.to_xml(xml))
          end
        end
        if notes_val = @notes
          xml.element("notes") do
            notes_val.each(&.to_xml(xml))
          end
        end
        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class Issue
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter issue_type : String?
    getter id : String?
    getter name : String?
    getter description : String?
    getter source : IssueSource?

    def initialize(@issue_type : String? = nil, @id : String? = nil,
                   @name : String? = nil, @description : String? = nil,
                   @source : IssueSource? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if it = @issue_type
        attrs["type"] = it
      end
      xml.element("issue", attributes: attrs) do
        if id = @id
          xml.element("id") { xml.text id }
        end
        if name = @name
          xml.element("name") { xml.text name }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
        @source.try(&.to_xml(xml))
      end
    end
  end

  class IssueSource
    include JSON::Serializable

    getter name : String?
    getter url : String?

    def initialize(@name : String? = nil, @url : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("source") do
        if name = @name
          xml.element("name") { xml.text name }
        end
        if url = @url
          xml.element("url") { xml.text url }
        end
      end
    end
  end

  class Note
    include JSON::Serializable

    getter locale : String?
    getter text : AttachedText?

    def initialize(@locale : String? = nil, @text : AttachedText? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("note") do
        if locale = @locale
          xml.element("locale") { xml.text locale }
        end
        @text.try(&.to_xml(xml))
      end
    end
  end

  class Swid
    include JSON::Serializable

    @[JSON::Field(key: "tagId")]
    getter tag_id : String
    getter name : String
    getter version : String?
    @[JSON::Field(key: "tagVersion")]
    getter tag_version : Int32?
    getter patch : Bool?
    getter text : AttachedText?
    getter url : String?

    def initialize(@tag_id : String, @name : String, @version : String? = nil,
                   @tag_version : Int32? = nil, @patch : Bool? = nil,
                   @text : AttachedText? = nil, @url : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {"tagId" => @tag_id, "name" => @name} of String => String
      if version = @version
        attrs["version"] = version
      end
      if tv = @tag_version
        attrs["tagVersion"] = tv.to_s
      end
      if patch = @patch
        attrs["patch"] = patch.to_s
      end
      xml.element("swid", attributes: attrs) do
        @text.try(&.to_xml(xml))
        if url = @url
          xml.element("url") { xml.text url }
        end
      end
    end
  end

  class ModelCard
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    @[JSON::Field(key: "modelParameters")]
    getter model_parameters : ModelParameters?
    getter considerations : ModelConsiderations?

    def initialize(@bom_ref : String? = nil, @model_parameters : ModelParameters? = nil,
                   @considerations : ModelConsiderations? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      xml.element("modelCard", attributes: attrs) do
        @model_parameters.try(&.to_xml(xml))
        @considerations.try(&.to_xml(xml))
      end
    end
  end

  class ModelParameters
    include JSON::Serializable

    getter approach : ModelApproach?
    getter task : String?
    @[JSON::Field(key: "architectureFamily")]
    getter architecture_family : String?
    @[JSON::Field(key: "modelArchitecture")]
    getter model_architecture : String?
    getter datasets : Array(ComponentData)?
    getter inputs : Array(ModelIO)?
    getter outputs : Array(ModelIO)?

    def initialize(@approach : ModelApproach? = nil, @task : String? = nil,
                   @architecture_family : String? = nil, @model_architecture : String? = nil,
                   @datasets : Array(ComponentData)? = nil,
                   @inputs : Array(ModelIO)? = nil, @outputs : Array(ModelIO)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("modelParameters") do
        @approach.try(&.to_xml(xml))
        if task = @task
          xml.element("task") { xml.text task }
        end
        if af = @architecture_family
          xml.element("architectureFamily") { xml.text af }
        end
        if ma = @model_architecture
          xml.element("modelArchitecture") { xml.text ma }
        end
        if datasets_val = @datasets
          xml.element("datasets") do
            datasets_val.each(&.to_xml(xml))
          end
        end
        if inputs_val = @inputs
          xml.element("inputs") do
            inputs_val.each { |io| io.to_xml(xml, "input") }
          end
        end
        if outputs_val = @outputs
          xml.element("outputs") do
            outputs_val.each { |io| io.to_xml(xml, "output") }
          end
        end
      end
    end
  end

  class ModelApproach
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter approach_type : String?

    def initialize(@approach_type : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("approach") do
        if at = @approach_type
          xml.element("type") { xml.text at }
        end
      end
    end
  end

  class ModelIO
    include JSON::Serializable

    getter format : String?

    def initialize(@format : String? = nil)
    end

    def to_xml(xml : XML::Builder, element_name : String = "input")
      xml.element(element_name) do
        if fmt = @format
          xml.element("format") { xml.text fmt }
        end
      end
    end
  end

  class ModelConsiderations
    include JSON::Serializable

    getter users : Array(String)?
    @[JSON::Field(key: "useCases")]
    getter use_cases : Array(String)?
    @[JSON::Field(key: "technicalLimitations")]
    getter technical_limitations : Array(String)?
    @[JSON::Field(key: "performanceMetrics")]
    getter performance_metrics : Array(PerformanceMetric)?
    @[JSON::Field(key: "ethicalConsiderations")]
    getter ethical_considerations : Array(String)?
    @[JSON::Field(key: "fairnessAssessments")]
    getter fairness_assessments : Array(FairnessAssessment)?

    def initialize(@users : Array(String)? = nil, @use_cases : Array(String)? = nil,
                   @technical_limitations : Array(String)? = nil,
                   @performance_metrics : Array(PerformanceMetric)? = nil,
                   @ethical_considerations : Array(String)? = nil,
                   @fairness_assessments : Array(FairnessAssessment)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("considerations") do
        if users_val = @users
          xml.element("users") do
            users_val.each { |u| xml.element("user") { xml.text u } }
          end
        end
        if uc = @use_cases
          xml.element("useCases") do
            uc.each { |u| xml.element("useCase") { xml.text u } }
          end
        end
        if tl = @technical_limitations
          xml.element("technicalLimitations") do
            tl.each { |t| xml.element("technicalLimitation") { xml.text t } }
          end
        end
        if pm = @performance_metrics
          xml.element("performanceMetrics") do
            pm.each(&.to_xml(xml))
          end
        end
        if ec = @ethical_considerations
          xml.element("ethicalConsiderations") do
            ec.each { |e| xml.element("ethicalConsideration") { xml.text e } }
          end
        end
        if fa = @fairness_assessments
          xml.element("fairnessAssessments") do
            fa.each(&.to_xml(xml))
          end
        end
      end
    end
  end

  class PerformanceMetric
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter metric_type : String?
    getter value : String?
    getter slice : String?
    @[JSON::Field(key: "confidenceInterval")]
    getter confidence_interval : ConfidenceInterval?

    def initialize(@metric_type : String? = nil, @value : String? = nil,
                   @slice : String? = nil, @confidence_interval : ConfidenceInterval? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("performanceMetric") do
        if mt = @metric_type
          xml.element("type") { xml.text mt }
        end
        if v = @value
          xml.element("value") { xml.text v }
        end
        if s = @slice
          xml.element("slice") { xml.text s }
        end
        @confidence_interval.try(&.to_xml(xml))
      end
    end
  end

  class ConfidenceInterval
    include JSON::Serializable

    @[JSON::Field(key: "lowerBound")]
    getter lower_bound : String?
    @[JSON::Field(key: "upperBound")]
    getter upper_bound : String?

    def initialize(@lower_bound : String? = nil, @upper_bound : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("confidenceInterval") do
        if lb = @lower_bound
          xml.element("lowerBound") { xml.text lb }
        end
        if ub = @upper_bound
          xml.element("upperBound") { xml.text ub }
        end
      end
    end
  end

  class FairnessAssessment
    include JSON::Serializable

    @[JSON::Field(key: "groupAtRisk")]
    getter group_at_risk : String?
    @[JSON::Field(key: "benefits")]
    getter benefits : String?
    @[JSON::Field(key: "harms")]
    getter harms : String?
    @[JSON::Field(key: "mitigationStrategy")]
    getter mitigation_strategy : String?

    def initialize(@group_at_risk : String? = nil, @benefits : String? = nil,
                   @harms : String? = nil, @mitigation_strategy : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("fairnessAssessment") do
        if gar = @group_at_risk
          xml.element("groupAtRisk") { xml.text gar }
        end
        if b = @benefits
          xml.element("benefits") { xml.text b }
        end
        if h = @harms
          xml.element("harms") { xml.text h }
        end
        if ms = @mitigation_strategy
          xml.element("mitigationStrategy") { xml.text ms }
        end
      end
    end
  end

  class ComponentData
    include JSON::Serializable

    @[JSON::Field(key: "bom-ref")]
    getter bom_ref : String?
    @[JSON::Field(key: "type")]
    getter data_type : String?
    getter name : String?
    getter description : String?

    VALID_DATA_TYPES = [
      "source-code", "configuration", "dataset", "definition",
      "other",
    ]

    def initialize(@data_type : String? = nil, @name : String? = nil,
                   @description : String? = nil, @bom_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      attrs = {} of String => String
      if bom_ref_val = @bom_ref
        attrs["bom-ref"] = bom_ref_val
      end
      xml.element("dataset", attributes: attrs) do
        if dt = @data_type
          xml.element("type") { xml.text dt }
        end
        if name = @name
          xml.element("name") { xml.text name }
        end
        if description = @description
          xml.element("description") { xml.text description }
        end
      end
    end
  end

  class CryptoProperties
    include JSON::Serializable

    @[JSON::Field(key: "assetType")]
    getter asset_type : String?
    @[JSON::Field(key: "algorithmProperties")]
    getter algorithm_properties : AlgorithmProperties?
    @[JSON::Field(key: "certificateProperties")]
    getter certificate_properties : CertificateProperties?
    getter oid : String?

    def initialize(@asset_type : String? = nil, @algorithm_properties : AlgorithmProperties? = nil,
                   @certificate_properties : CertificateProperties? = nil, @oid : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("cryptoProperties") do
        if at = @asset_type
          xml.element("assetType") { xml.text at }
        end
        @algorithm_properties.try(&.to_xml(xml))
        @certificate_properties.try(&.to_xml(xml))
        if oid = @oid
          xml.element("oid") { xml.text oid }
        end
      end
    end
  end

  class AlgorithmProperties
    include JSON::Serializable

    getter primitive : String?
    @[JSON::Field(key: "parameterSetIdentifier")]
    getter parameter_set_identifier : String?
    getter curve : String?
    @[JSON::Field(key: "executionEnvironment")]
    getter execution_environment : String?
    @[JSON::Field(key: "implementationPlatform")]
    getter implementation_platform : String?
    getter mode : String?
    getter padding : String?
    @[JSON::Field(key: "cryptoFunctions")]
    getter crypto_functions : Array(String)?

    def initialize(@primitive : String? = nil, @parameter_set_identifier : String? = nil,
                   @curve : String? = nil, @execution_environment : String? = nil,
                   @implementation_platform : String? = nil, @mode : String? = nil,
                   @padding : String? = nil, @crypto_functions : Array(String)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("algorithmProperties") do
        if p = @primitive
          xml.element("primitive") { xml.text p }
        end
        if psi = @parameter_set_identifier
          xml.element("parameterSetIdentifier") { xml.text psi }
        end
        if c = @curve
          xml.element("curve") { xml.text c }
        end
        if ee = @execution_environment
          xml.element("executionEnvironment") { xml.text ee }
        end
        if ip = @implementation_platform
          xml.element("implementationPlatform") { xml.text ip }
        end
        if m = @mode
          xml.element("mode") { xml.text m }
        end
        if pad = @padding
          xml.element("padding") { xml.text pad }
        end
        if cf = @crypto_functions
          xml.element("cryptoFunctions") do
            cf.each { |f| xml.element("cryptoFunction") { xml.text f } }
          end
        end
      end
    end
  end

  class CertificateProperties
    include JSON::Serializable

    @[JSON::Field(key: "subjectName")]
    getter subject_name : String?
    @[JSON::Field(key: "issuerName")]
    getter issuer_name : String?
    @[JSON::Field(key: "notValidBefore")]
    getter not_valid_before : String?
    @[JSON::Field(key: "notValidAfter")]
    getter not_valid_after : String?
    @[JSON::Field(key: "signatureAlgorithmRef")]
    getter signature_algorithm_ref : String?

    def initialize(@subject_name : String? = nil, @issuer_name : String? = nil,
                   @not_valid_before : String? = nil, @not_valid_after : String? = nil,
                   @signature_algorithm_ref : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("certificateProperties") do
        if sn = @subject_name
          xml.element("subjectName") { xml.text sn }
        end
        if in_val = @issuer_name
          xml.element("issuerName") { xml.text in_val }
        end
        if nvb = @not_valid_before
          xml.element("notValidBefore") { xml.text nvb }
        end
        if nva = @not_valid_after
          xml.element("notValidAfter") { xml.text nva }
        end
        if sar = @signature_algorithm_ref
          xml.element("signatureAlgorithmRef") { xml.text sar }
        end
      end
    end
  end
end
