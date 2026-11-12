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

  # The names declared by the `name -> source details` dependency maps.
  @[YAML::Field(converter: ShardFile::DependencyNames)]
  @dependencies = Set(String).new
  @[YAML::Field(converter: ShardFile::DependencyNames)]
  @development_dependencies = Set(String).new

  # Build targets (name -> {main: ...}). Their presence is what distinguishes an
  # application shard from a library one.
  getter targets : YAML::Any?

  # True when the shard declares at least one build target.
  def targets? : Bool
    !!@targets.try(&.as_h?).try { |targets| !targets.empty? }
  end

  # Returns the set of dependency names declared as runtime dependencies.
  def runtime_dependency_names : Set(String)
    @dependencies
  end

  # Returns the set of dependency names declared as development dependencies.
  def dev_dependency_names : Set(String)
    @development_dependencies
  end

  # Collects the keys of a `name -> source details` dependency mapping. A
  # non-mapping node is not a dependency declaration, so it contributes nothing
  # rather than raising. shards reads every key as the scalar's text, so a key
  # the YAML core schema types otherwise is still that name: `2048:` and
  # `true:`, and `010:` as `010`, not the integer 8 it resolves to. Only a null
  # or blank key is dropped.
  module DependencyNames
    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Set(String)
      names = Set(String).new
      node = resolve(node)
      return names unless node.is_a?(YAML::Nodes::Mapping)
      # `Core.each` expands `<<` merge keys, as YAML::Any did.
      YAML::Schema::Core.each(node) do |key, _|
        key = resolve(key)
        next unless key.is_a?(YAML::Nodes::Scalar)
        next if YAML::Schema::Core.parse_null?(key)
        key.value.presence.try { |name| names << name }
      end
      names
    end

    private def self.resolve(node : YAML::Nodes::Node?) : YAML::Nodes::Node?
      node.is_a?(YAML::Nodes::Alias) ? node.value : node
    end
  end
end
