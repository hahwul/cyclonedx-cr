require "yaml"

# Represents the structure of a `shard.yml` file.
# This class is used to parse the main project's metadata
# such as its name and version.
class ShardFile
  include YAML::Serializable

  # The name of the project/shard.
  getter name : String
  # The version of the project/shard. Optional because a `shard.yml` may omit it
  # (e.g. an application that is never published), in which case it stays nil and
  # the generated component simply carries no `version` — which is what
  # CycloneDX means by an unknown version. A blank `version: ""` means the same
  # thing, so it reads as absent rather than producing an empty version.
  @version : String?

  def version : String?
    @version.presence
  end

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

  # Build targets (name -> {main: ...}). Their presence is what distinguishes an
  # application shard from a library one.
  getter targets : YAML::Any?

  # True when the shard declares at least one build target.
  def targets? : Bool
    !!@targets.try(&.as_h?).try { |targets| !targets.empty? }
  end

  # Returns the set of dependency names declared as runtime dependencies.
  def runtime_dependency_names : Set(String)
    dependency_names(@dependencies)
  end

  # Returns the set of dependency names declared as development dependencies.
  def dev_dependency_names : Set(String)
    dependency_names(@development_dependencies)
  end

  # Collects the keys of a `name -> source details` dependency mapping. A
  # non-mapping node is not a dependency declaration, so it contributes nothing
  # rather than raising. shards reads every key as a string, so a scalar key the
  # YAML core schema types otherwise (`2048:`, `true:`) is still a name; only a
  # null or blank key is dropped.
  private def dependency_names(node : YAML::Any?) : Set(String)
    names = Set(String).new
    if mapping = node.try(&.as_h?)
      mapping.each_key do |key|
        next if key.as_a? || key.as_h?
        key.raw.to_s.presence.try { |name| names << name }
      end
    end
    names
  end
end
