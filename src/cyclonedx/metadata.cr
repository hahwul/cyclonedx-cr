require "json"
require "xml"
require "./component"
require "./models"

module CycloneDX
  class Metadata
    include JSON::Serializable

    getter component : Component?
    getter tools : Array(Tool)?
    getter authors : Array(OrganizationalContact)?

    def initialize(@component : Component? = nil, @tools : Array(Tool)? = nil, @authors : Array(OrganizationalContact)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("metadata") do
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
      end
    end
  end
end
