require "option_parser"
require "./cyclonedx/bom"
require "./cyclonedx/component"
require "./cyclonedx/models"
require "./cyclonedx/metadata"
require "./shard/shard_file"
require "./shard/shard_lock_file"

# Main application class for generating CycloneDX SBOMs from Crystal Shard files.
# Handles command-line argument parsing, file reading, and SBOM generation.
class App
  VERSION            = "1.0.2"
  SUPPORTED_VERSIONS = ["1.4", "1.5", "1.6", "1.7"]
  SUPPORTED_FORMATS  = ["json", "xml", "csv"]
  DEFAULT_VERSION    = "1.6"
  DEFAULT_FORMAT     = "json"
  DEFAULT_SHARD_FILE = "shard.yml"
  DEFAULT_LOCK_FILE  = "shard.lock"

  # Regex patterns for parsing Git URLs
  private GITHUB_URL_PATTERN = /.*github\.com[\/:]/
  private GIT_SUFFIX_PATTERN = /\.git$/

  # Holds parsed command-line options.
  record Options,
    shard_file : String,
    shard_lock_file : String,
    output_file : String,
    spec_version : String,
    output_format : String

  # Runs the main application logic.
  def run
    options = parse_options
    return unless validate_options(options)
    return unless validate_input_files(options)

    bom = generate_bom(options)
    write_output(bom, options)
  end

  # Parses command-line options and returns an Options record.
  private def parse_options : Options
    shard_file = DEFAULT_SHARD_FILE
    shard_lock_file = DEFAULT_LOCK_FILE
    output_file = ""
    spec_version = DEFAULT_VERSION
    output_format = DEFAULT_FORMAT

    OptionParser.parse do |parser|
      parser.banner = "Usage: cyclonedx-cr [arguments]"
      parser.on("-i FILE", "--input=FILE", "shard.lock file path (default: #{DEFAULT_LOCK_FILE})") { |file| shard_lock_file = file }
      parser.on("-s FILE", "--shard=FILE", "shard.yml file path (default: #{DEFAULT_SHARD_FILE})") { |file| shard_file = file }
      parser.on("-o FILE", "--output=FILE", "Output file path (default: stdout)") { |file| output_file = file }
      parser.on("--spec-version VERSION", "CycloneDX spec version (options: #{SUPPORTED_VERSIONS.join(", ")}, default: #{DEFAULT_VERSION})") { |v| spec_version = v }
      parser.on("--output-format FORMAT", "Output format (options: #{SUPPORTED_FORMATS.join(", ")}, default: #{DEFAULT_FORMAT})") { |format| output_format = format.downcase }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
    end

    Options.new(
      shard_file: shard_file,
      shard_lock_file: shard_lock_file,
      output_file: output_file,
      spec_version: spec_version,
      output_format: output_format
    )
  end

  # Validates the parsed options.
  private def validate_options(options : Options) : Bool
    unless SUPPORTED_VERSIONS.includes?(options.spec_version)
      STDERR.puts "Error: Unsupported spec version '#{options.spec_version}'. Supported versions are: #{SUPPORTED_VERSIONS.join(", ")}"
      return false
    end

    unless SUPPORTED_FORMATS.includes?(options.output_format)
      STDERR.puts "Error: Unsupported output format '#{options.output_format}'. Supported formats are: #{SUPPORTED_FORMATS.join(", ")}"
      return false
    end

    true
  end

  # Validates that required input files exist.
  private def validate_input_files(options : Options) : Bool
    unless File.exists?(options.shard_file)
      STDERR.puts "Error: `#{options.shard_file}` not found."
      return false
    end

    unless File.exists?(options.shard_lock_file)
      STDERR.puts "Error: `#{options.shard_lock_file}` not found."
      return false
    end

    true
  end

  # Generates the BOM from input files.
  private def generate_bom(options : Options) : CycloneDX::BOM
    main_component = parse_main_component(options.shard_file)
    dependencies = parse_dependencies(options.shard_lock_file)

    tool = CycloneDX::Tool.new(vendor: "hahwul", name: "cyclonedx-cr", version: VERSION)
    metadata = CycloneDX::Metadata.new(component: main_component, tools: [tool])

    CycloneDX::BOM.new(
      spec_version: options.spec_version,
      metadata: metadata,
      components: dependencies
    )
  end

  # Writes the BOM output to file or stdout.
  private def write_output(bom : CycloneDX::BOM, options : Options) : Nil
    output_content = serialize_bom(bom, options.output_format)

    if options.output_file.empty?
      puts output_content
    else
      File.write(options.output_file, output_content)
      STDERR.puts "SBOM successfully written to #{options.output_file} in #{options.output_format.upcase} format."
    end
  end

  # Serializes the BOM to the specified format.
  private def serialize_bom(bom : CycloneDX::BOM, format : String) : String
    case format
    when "json" then bom.to_json
    when "xml"  then bom.to_xml
    when "csv"  then bom.to_csv
    else             "" # Should not happen due to validation
    end
  end

  # Parses the main component information from `shard.yml`.
  #
  # @param file_path [String] The path to the `shard.yml` file.
  # @return [CycloneDX::Component] The main application component.
  private def parse_main_component(file_path : String) : CycloneDX::Component
    shard = ShardFile.from_yaml(File.read(file_path))

    licenses = [] of CycloneDX::License
    if license_name = shard.license
      licenses << CycloneDX::License.new(name: license_name)
    end

    external_refs = [] of CycloneDX::ExternalReference
    if homepage = shard.homepage
      external_refs << CycloneDX::ExternalReference.new(ref_type: "website", url: homepage)
    end
    if repository = shard.repository
      external_refs << CycloneDX::ExternalReference.new(ref_type: "vcs", url: repository)
    end

    author = shard.authors.try(&.first?)

    CycloneDX::Component.new(
      component_type: "application",
      name: shard.name,
      version: shard.version,
      description: shard.description,
      author: author,
      licenses: licenses.empty? ? nil : licenses,
      external_references: external_refs.empty? ? nil : external_refs
    )
  end

  # Parses dependency components from `shard.lock`.
  #
  # @param file_path [String] The path to the `shard.lock` file.
  # @return [Array(CycloneDX::Component)] An array of dependency components.
  private def parse_dependencies(file_path : String) : Array(CycloneDX::Component)
    lock_file = ShardLockFile.from_yaml(File.read(file_path))
    lock_file.shards.map do |name, details|
      CycloneDX::Component.new(
        name: name,
        version: details.version,
        purl: generate_purl(details)
      )
    end
  end

  # Generates a Package URL (PURL) for a given shard based on its details.
  # Currently supports GitHub-based PURLs.
  #
  # @param details [ShardLockEntry] The details of the shard from `shard.lock`.
  # @return [String?] The generated PURL, or `nil` if one cannot be determined.
  private def generate_purl(details : ShardLockEntry) : String?
    if github_repo = details.github
      "pkg:github/#{github_repo}@#{details.version}"
    elsif git_url = details.git
      parse_github_repo_from_git_url(git_url).try { |repo| "pkg:github/#{repo}@#{details.version}" }
    else
      nil
    end
  end

  # Extracts the GitHub repository path from a Git URL.
  #
  # @param git_url [String] The Git URL.
  # @return [String?] The GitHub repository path (e.g., "owner/repo"), or `nil` if not a GitHub URL.
  private def parse_github_repo_from_git_url(git_url : String) : String?
    return nil unless git_url.includes?("github.com")
    git_url.sub(GITHUB_URL_PATTERN, "").sub(GIT_SUFFIX_PATTERN, "")
  end
end
