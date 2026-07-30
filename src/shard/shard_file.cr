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
  # CycloneDX means by an unknown version.
  getter version : String?

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
  # non-mapping node (or a non-string key) is not a dependency declaration, so
  # it contributes nothing rather than raising.
  private def dependency_names(node : YAML::Any?) : Set(String)
    names = Set(String).new
    if mapping = node.try(&.as_h?)
      mapping.each_key { |key| key.as_s?.try { |s| names << s } }
    end
    names
  end
end
