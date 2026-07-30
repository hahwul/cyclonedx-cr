require "json"
require "xml"
# `Pedigree` holds arrays of `Component`, which in turn requires this file.
# Crystal resolves the cycle by ignoring the second `require`, and this keeps the
# file usable on its own.
require "./component"

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

    # `ancestors`, `descendants` and `variants` are arrays of full components.
    # Describing where a component came from is the whole point of pedigree, so
    # without them the type could not express its own purpose.
    getter ancestors : Array(Component)?
    getter descendants : Array(Component)?
    getter variants : Array(Component)?
    getter commits : Array(Commit)?
    getter patches : Array(Patch)?
    getter notes : String?

    def initialize(@notes : String? = nil, @commits : Array(Commit)? = nil,
                   @patches : Array(Patch)? = nil,
                   @ancestors : Array(Component)? = nil,
                   @descendants : Array(Component)? = nil,
                   @variants : Array(Component)? = nil)
    end

    def to_xml(xml : XML::Builder)
      # Element order follows the pedigreeType XSD <sequence>: ancestors,
      # descendants, variants, commits, patches, notes.
      xml.element("pedigree") do
        if ancestors_val = @ancestors
          xml.element("ancestors") { ancestors_val.each(&.to_xml(xml)) }
        end
        if descendants_val = @descendants
          xml.element("descendants") { descendants_val.each(&.to_xml(xml)) }
        end
        if variants_val = @variants
          xml.element("variants") { variants_val.each(&.to_xml(xml)) }
        end
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
