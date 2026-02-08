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
end
