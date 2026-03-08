require "yaml"

# Represents the structure of a `shard.yml` file.
# This class is used to parse the main project's metadata
# such as its name and version.
class ShardFile
  include YAML::Serializable

  # The name of the project/shard.
  getter name : String
  # The version of the project/shard.
  getter version : String

  # Optional fields
  getter description : String?
  getter authors : Array(String)?
  getter license : String?
  getter homepage : String?
  getter repository : String?

  # Dependency maps (name -> source details)
  getter dependencies : YAML::Any?
  @[YAML::Field(key: "development_dependencies")]
  getter development_dependencies : YAML::Any?

  # Returns the set of dependency names declared as development dependencies.
  def dev_dependency_names : Set(String)
    names = Set(String).new
    if dev_deps = @development_dependencies
      if mapping = dev_deps.as_h?
        mapping.each_key { |key| names << key.as_s }
      end
    end
    names
  end
end
