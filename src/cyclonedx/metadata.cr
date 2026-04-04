require "json"
require "xml"
require "./component"
require "./models"

module CycloneDX
  class Metadata
    include JSON::Serializable

    getter timestamp : String?
    getter lifecycles : Array(Lifecycle)?
    getter manufacture : OrganizationalEntity?
    getter supplier : OrganizationalEntity?
    getter component : Component?
    getter tools : Array(Tool)?
    getter authors : Array(OrganizationalContact)?
    getter properties : Array(Property)?

    def initialize(@component : Component? = nil, @tools : Array(Tool)? = nil,
                   @authors : Array(OrganizationalContact)? = nil, @timestamp : String? = nil,
                   @properties : Array(Property)? = nil, @lifecycles : Array(Lifecycle)? = nil,
                   @manufacture : OrganizationalEntity? = nil, @supplier : OrganizationalEntity? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("metadata") do
        if ts = @timestamp
          xml.element("timestamp") { xml.text ts }
        end
        if lifecycles_val = @lifecycles
          xml.element("lifecycles") do
            lifecycles_val.each(&.to_xml(xml))
          end
        end
        if tools_val = @tools
          xml.element("tools") do
            tools_val.each(&.to_xml(xml))
          end
        end
        if authors_val = @authors
          xml.element("authors") do
            authors_val.each(&.to_xml(xml))
          end
        end
        @component.try(&.to_xml(xml))
        @manufacture.try(&.to_xml(xml, "manufacture"))
        @supplier.try(&.to_xml(xml, "supplier"))

        if props = @properties
          xml.element("properties") do
            props.each(&.to_xml(xml))
          end
        end
      end
    end
  end
end
