require "yaml"

# Represents the structure of a `shard.yml` file.
# This class is used to parse the main project's metadata
# such as its name and version.
class ShardFile
  include YAML::Serializable
  # The name of the project/shard.
  property name : String
  # The version of the project/shard.
  property version : String
end
