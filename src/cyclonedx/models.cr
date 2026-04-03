require "json"
require "xml"

module CycloneDX
  class License
    include JSON::Serializable

    getter id : String?
    getter name : String?
    getter url : String?

    def initialize(@id : String? = nil, @name : String? = nil, @url : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("license") do
        if id_val = @id
          xml.element("id") { xml.text id_val }
        elsif name_val = @name
          xml.element("name") { xml.text name_val }
        end
        if url_val = @url
          xml.element("url") { xml.text url_val }
        end
      end
    end
  end

  class LicenseExpression
    include JSON::Serializable

    getter expression : String

    def initialize(@expression : String)
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

    def initialize(@ref : String, @depends_on : Array(String) = [] of String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("dependency", attributes: {"ref" => @ref}) do
        @depends_on.each do |dep_ref|
          xml.element("dependency", attributes: {"ref" => dep_ref})
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
end
