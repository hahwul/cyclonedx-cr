
require "json"
require "yaml"
require "option_parser"

# CycloneDX Data Models
# Based on CycloneDX v1.4 JSON Schema

class CycloneDX::Component
  include JSON::Serializable

  @[JSON::Field(key: "type")]
  property component_type : String
  property name : String
  property version : String
  property purl : String?

  def initialize(@name : String, @version : String, @component_type = "library", @purl = nil)
  end
end

class CycloneDX::BOM
  include JSON::Serializable

  @[JSON::Field(key: "bomFormat")]
  property bom_format : String
  @[JSON::Field(key: "specVersion")]
  property spec_version : String
  property version : Int32
  property components : Array(Component)

  def initialize(@components : Array(Component), @bom_format = "CycloneDX", @spec_version = "1.4", @version = 1)
  end
end

# Shard file Data Models
class ShardFile
  include YAML::Serializable

  property name : String
  property version : String
end

class ShardLockFile
  include YAML::Serializable

  property shards : Hash(String, ShardLockEntry)
end

class ShardLockEntry
  include YAML::Serializable

  property version : String
  property git : String?
  property github : String?
  property path : String?
end

# Main Application Logic
class App
  def run
    shard_file = "shard.yml"
    shard_lock_file = "shard.lock"
    output_file = ""
    spec_version = "1.6" # Default to latest
    supported_versions = ["1.4", "1.5", "1.6"]

    OptionParser.parse do |parser|
      parser.banner = "Usage: cyclonedx-cr [arguments]"
      parser.on("-i FILE", "--input=FILE", "shard.lock file path (default: shard.lock)") { |f| shard_lock_file = f }
      parser.on("-s FILE", "--shard=FILE", "shard.yml file path (default: shard.yml)") { |f| shard_file = f }
      parser.on("-o FILE", "--output=FILE", "Output file path (default: stdout)") { |f| output_file = f }
      parser.on("--spec-version VERSION", "CycloneDX spec version (options: #{supported_versions.join(", ")}, default: #{spec_version})") { |v| spec_version = v }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        next
      end
    end

    unless supported_versions.includes?(spec_version)
      puts "Error: Unsupported spec version '#{spec_version}'. Supported versions are: #{supported_versions.join(", ")}"
      return
    end

    unless File.exists?(shard_file)
      puts "Error: `#{shard_file}` not found."
      return
    end

    unless File.exists?(shard_lock_file)
      puts "Error: `#{shard_lock_file}` not found."
      return
    end

    # Parse shard.yml for main project info
    main_component = parse_main_component(shard_file)

    # Parse shard.lock for dependencies
    dependencies = parse_dependencies(shard_lock_file)

    # Create BOM
    bom = CycloneDX::BOM.new(
      spec_version: spec_version,
      components: [main_component] + dependencies
    )

    # Output JSON
    json_output = bom.to_json

    if output_file.empty?
      puts json_output
    else
      File.write(output_file, json_output)
      puts "SBOM successfully written to #{output_file}"
    end
  end

  private def parse_main_component(file_path : String) : CycloneDX::Component
    shard = ShardFile.from_yaml(File.read(file_path))
    CycloneDX::Component.new(
      component_type: "application",
      name: shard.name,
      version: shard.version
    )
  end

  private def parse_dependencies(file_path : String) : Array(CycloneDX::Component)
    lock_file = ShardLockFile.from_yaml(File.read(file_path))
    components = [] of CycloneDX::Component

    lock_file.shards.each do |name, details|
      purl = generate_purl(name, details)
      components << CycloneDX::Component.new(
        name: name,
        version: details.version,
        purl: purl
      )
    end

    components
  end

  private def generate_purl(name : String, details : ShardLockEntry) : String?
    if github_repo = details.github
      return "pkg:github/#{github_repo}@#{details.version}"
    elsif git_url = details.git
      # Attempt to parse a github URL from a generic git url
      if git_url.includes?("github.com")
        repo = git_url.sub(/.*github.com\//, "").sub(/\.git$/, "")
        return "pkg:github/#{repo}@#{details.version}"
      end
    end
    # For local paths or other sources, purl might be omitted
    nil
  end
end

# Run the application
App.new.run
