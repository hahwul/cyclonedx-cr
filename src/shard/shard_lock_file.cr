require "yaml"

# Represents the structure of a `shard.lock` file.
# This file contains the resolved dependencies of the project.
class ShardLockFile
  include YAML::Serializable

  # A hash mapping shard names to their `ShardLockEntry` details.
  getter shards : Hash(String, ShardLockEntry) = {} of String => ShardLockEntry
end

# Represents a single entry within the `shards` section of a `shard.lock` file.
# It provides details about a specific dependency.
class ShardLockEntry
  include YAML::Serializable

  # The version of the locked dependency.
  getter version : String
  # The Git URL if the dependency is sourced from a Git repository.
  getter git : String?
  # The GitHub repository path (e.g., "owner/repo") if sourced from GitHub.
  getter github : String?
  # The local path if the dependency is a local path dependency.
  getter path : String?
end
