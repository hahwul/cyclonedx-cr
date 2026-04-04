require "json"
require "xml"

module CycloneDX
  class Commit
    include JSON::Serializable

    getter uid : String?
    getter url : String?
    getter message : String?

    def initialize(@uid : String? = nil, @url : String? = nil, @message : String? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("commit") do
        if uid = @uid
          xml.element("uid") { xml.text uid }
        end
        if url = @url
          xml.element("url") { xml.text url }
        end
        if message = @message
          xml.element("message") { xml.text message }
        end
      end
    end
  end

  class Patch
    include JSON::Serializable

    @[JSON::Field(key: "type")]
    getter patch_type : String

    def initialize(@patch_type : String)
    end

    def to_xml(xml : XML::Builder)
      xml.element("patch", attributes: {"type" => @patch_type})
    end
  end

  class Pedigree
    include JSON::Serializable

    getter notes : String?
    getter commits : Array(Commit)?
    getter patches : Array(Patch)?

    def initialize(@notes : String? = nil, @commits : Array(Commit)? = nil,
                   @patches : Array(Patch)? = nil)
    end

    def to_xml(xml : XML::Builder)
      xml.element("pedigree") do
        if commits_val = @commits
          xml.element("commits") do
            commits_val.each(&.to_xml(xml))
          end
        end
        if patches_val = @patches
          xml.element("patches") do
            patches_val.each(&.to_xml(xml))
          end
        end
        if notes = @notes
          xml.element("notes") { xml.text notes }
        end
      end
    end
  end
end
