require "json"
require "xml"
require "yaml"
require "csv"
require "option_parser"
require "uuid"

# CycloneDX Data Models

class CycloneDX::Component
  include JSON::Serializable

  @[JSON::Field(key: "type")]
  property component_type : String
  property name : String
  property version : String
  property purl : String?

  def initialize(@name : String, @version : String, @component_type = "library", @purl = nil)
  end

  def to_xml(builder : XML::Builder)
    builder.element("component", attributes: {"type": @component_type}) do
      builder.element("name") { builder.text(@name) }
      builder.element("version") { builder.text(@version) }
      if @purl
        builder.element("purl") { builder.text(@purl.as(String)) }
      end
    end
  end
end

class CycloneDX::BOM
  include JSON::Serializable

  @[JSON::Field(key: "bomFormat")]
  property bom_format_json : String = "CycloneDX"
  @[JSON::Field(key: "specVersion")]
  property spec_version_json : String
  @[JSON::Field(key: "version")]
  property version_json : Int32 = 1
  property components : Array(Component)

  @spec_version : String

  def initialize(@components : Array(Component), spec_version : String)
    @spec_version_json = spec_version
    @spec_version = spec_version
  end

  def to_xml
    String.build do |str|
      XML.build(str) do |xml|
        xml.element("bom", attributes: {
          "xmlns": "http://cyclonedx.org/schema/bom/#{@spec_version}",
          "version": "1",
          "serialNumber": "urn:uuid:#{UUID.random}"
        }) do
          xml.element("components") do
            @components.each do |comp|
              comp.to_xml(xml)
            end
          end
        end
      end
    end
  end

  def to_csv
    CSV.build do |csv|
      csv.row "Name", "Version", "PURL", "Type"
      @components.each do |comp|
        csv.row comp.name, comp.version, comp.purl, comp.component_type
      end
    end
  end
end

# Shard file Data Models (unchanged)
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
    spec_version = "1.6"
    output_format = "json"
    supported_versions = ["1.4", "1.5", "1.6"]
    supported_formats = ["json", "xml", "csv"]

    OptionParser.parse do |parser|
      parser.banner = "Usage: cyclonedx-cr [arguments]"
      parser.on("-i FILE", "--input=FILE", "shard.lock file path (default: shard.lock)") { |f| shard_lock_file = f }
      parser.on("-s FILE", "--shard=FILE", "shard.yml file path (default: shard.yml)") { |f| shard_file = f }
      parser.on("-o FILE", "--output=FILE", "Output file path (default: stdout)") { |f| output_file = f }
      parser.on("--spec-version VERSION", "CycloneDX spec version (options: #{supported_versions.join(", ")}, default: #{spec_version})") { |v| spec_version = v }
      parser.on("--output-format FORMAT", "Output format (options: #{supported_formats.join(", ")}, default: #{output_format})") { |f| output_format = f.downcase }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
    end

    unless supported_versions.includes?(spec_version)
      puts "Error: Unsupported spec version '#{spec_version}'. Supported versions are: #{supported_versions.join(", ")}"
      return
    end

    unless supported_formats.includes?(output_format)
      puts "Error: Unsupported output format '#{output_format}'. Supported formats are: #{supported_formats.join(", ")}"
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

    main_component = parse_main_component(shard_file)
    dependencies = parse_dependencies(shard_lock_file)

    bom = CycloneDX::BOM.new(
      spec_version: spec_version,
      components: [main_component] + dependencies
    )

    output_content = case output_format
                     when "json"
                       bom.to_json
                     when "xml"
                       bom.to_xml
                     when "csv"
                       bom.to_csv
                     else
                       "" # Should not happen due to validation above
                     end

    if output_file.empty?
      puts output_content
    else
      File.write(output_file, output_content)
      puts "SBOM successfully written to #{output_file} in #{output_format.upcase} format."
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
      if git_url.includes?("github.com")
        repo = git_url.sub(/.*github.com\//, "").sub(/\.git$/, "")
        return "pkg:github/#{repo}@#{details.version}"
      end
    end
    nil
  end
end

App.new.run