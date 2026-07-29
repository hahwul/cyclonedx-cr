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

  # Placeholder used when a lock entry carries no version of its own. It is a
  # marker for "not known", not a real version, so consumers must not present
  # it as one (see `App#build_purl`, which omits it from the PURL).
  UNKNOWN_VERSION = "unknown"

  # The version of the locked dependency. Optional because `path:` entries
  # (and some other lock formats) may omit it; defaults to `UNKNOWN_VERSION`.
  getter version : String = UNKNOWN_VERSION
  # The Git URL if the dependency is sourced from a Git repository.
  getter git : String?
  # The GitHub repository path (e.g., "owner/repo") if sourced from GitHub.
  getter github : String?
  # The GitLab repository path (e.g., "owner/repo") if sourced from GitLab.
  getter gitlab : String?
  # The local path if the dependency is a local path dependency.
  getter path : String?
end
