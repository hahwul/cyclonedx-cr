require "json"
require "xml"

module CycloneDX
  class License
    include JSON::Serializable

    getter id : String?
    getter name : String?

    def initialize(@id : String? = nil, @name : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("license") do
        if id_val = @id
          xml.element("id") { xml.text id_val }
        elsif name_val = @name
          xml.element("name") { xml.text name_val }
        end
      end
    end
  end

  class ExternalReference
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter ref_type : String
    getter url : String

    def initialize(@ref_type : String, @url : String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("reference", attributes: {"type" => @ref_type}) do
        xml.element("url") { xml.text @url }
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
        xml.element("vendor") { xml.text @vendor } if @vendor
        xml.element("name") { xml.text @name } if @name
        xml.element("version") { xml.text @version } if @version
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
        xml.element("name") { xml.text @name } if @name
        xml.element("email") { xml.text @email } if @email
        xml.element("phone") { xml.text @phone } if @phone
      end
    end
  end
end
