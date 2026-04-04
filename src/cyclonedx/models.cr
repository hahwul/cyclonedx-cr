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
      xml.element("expression") { xml.text @expression }
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

    def initialize(@ref_type : String, @url : String, @comment : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("reference", attributes: {"type" => @ref_type}) do
        xml.element("url") { xml.text @url }
        if comment_val = @comment
          xml.element("comment") { xml.text comment_val }
        end
      end
    end
  end

  class Dependency
    include JSON::Serializable

    getter ref : String
    @[JSON::Field(key: "dependsOn")]
    getter depends_on : Array(String)
    getter provides : Array(String)?

    def initialize(@ref : String, @depends_on : Array(String) = [] of String,
                   @provides : Array(String)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("dependency", attributes: {"ref" => @ref}) do
        @depends_on.each do |dep_ref|
          xml.element("dependency", attributes: {"ref" => dep_ref})
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

    def to_xml(xml : XML::Builder)
      xml.element("author") do
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
          contacts.each(&.to_xml(xml))
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
end
