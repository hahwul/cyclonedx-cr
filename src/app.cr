require "option_parser"
require "./cyclonedx/bom"
require "./cyclonedx/component"
require "./shard/shard_file"
require "./shard/shard_lock_file"

# Main application class for generating CycloneDX SBOMs from Crystal Shard files.
# Handles command-line argument parsing, file reading, and SBOM generation.
class App
  # Runs the main application logic.
  def run
    shard_file = "shard.yml"
    shard_lock_file = "shard.lock"
    output_file = ""
    spec_version = "1.6"
    output_format = "json"
    supported_versions = ["1.4", "1.5", "1.6"]
    supported_formats = ["json", "xml", "csv"]

    # Parse command-line options.
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

    # Validate spec version.
    unless supported_versions.includes?(spec_version)
      puts "Error: Unsupported spec version '#{spec_version}'. Supported versions are: #{supported_versions.join(", ")}"
      return
    end

    # Validate output format.
    unless supported_formats.includes?(output_format)
      puts "Error: Unsupported output format '#{output_format}'. Supported formats are: #{supported_formats.join(", ")}"
      return
    end

    # Check if input files exist.
    unless File.exists?(shard_file)
      puts "Error: `#{shard_file}` not found."
      return
    end

    unless File.exists?(shard_lock_file)
      puts "Error: `#{shard_lock_file}` not found."
      return
    end

    # Parse main component and dependencies.
    main_component = parse_main_component(shard_file)
    dependencies = parse_dependencies(shard_lock_file)

    # Create BOM.
    bom = CycloneDX::BOM.new(
      spec_version: spec_version,
      components: [main_component] + dependencies
    )

    # Generate output content based on format.
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

    # Write output to file or stdout.
    if output_file.empty?
      puts output_content
    else
      File.write(output_file, output_content)
      puts "SBOM successfully written to #{output_file} in #{output_format.upcase} format."
    end
  end

  # Parses the main component information from `shard.yml`.
  #
  # @param file_path [String] The path to the `shard.yml` file.
  # @return [CycloneDX::Component] The main application component.
  private def parse_main_component(file_path : String) : CycloneDX::Component
    shard = ShardFile.from_yaml(File.read(file_path))
    CycloneDX::Component.new(
      component_type: "application",
      name: shard.name,
      version: shard.version
    )
  end

  # Parses dependency components from `shard.lock`.
  #
  # @param file_path [String] The path to the `shard.lock` file.
  # @return [Array(CycloneDX::Component)] An array of dependency components.
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

  # Generates a Package URL (PURL) for a given shard based on its details.
  # Currently supports GitHub-based PURLs.
  #
  # @param name [String] The name of the shard.
  # @param details [ShardLockEntry] The details of the shard from `shard.lock`.
  # @return [String?] The generated PURL, or `nil` if one cannot be determined.
  private def generate_purl(name : String, details : ShardLockEntry) : String?
    case
    when github_repo = details.github
      "pkg:github/#{github_repo}@#{details.version}"
    when git_url = details.git
      if github_repo = parse_github_repo_from_git_url(git_url)
        "pkg:github/#{github_repo}@#{details.version}"
      else
        nil
      end
    else
      nil
    end
  end

  # Extracts the GitHub repository path from a Git URL.
  #
  # @param git_url [String] The Git URL.
  # @return [String?] The GitHub repository path (e.g., "owner/repo"), or `nil` if not a GitHub URL.
  private def parse_github_repo_from_git_url(git_url : String) : String?
    if git_url.includes?("github.com")
      git_url.sub(/.*github.com\//, "").sub(/\.git$/, "")
    else
      nil
    end
  end
end
