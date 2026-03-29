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
  VERSION            = "1.2.0"
  SUPPORTED_VERSIONS = ["1.4", "1.5", "1.6", "1.7"]
  SUPPORTED_FORMATS  = ["json", "xml", "csv"]
  DEFAULT_VERSION    = "1.6"
  DEFAULT_FORMAT     = "json"
  DEFAULT_SHARD_FILE = "shard.yml"
  DEFAULT_LOCK_FILE  = "shard.lock"

  COMPONENT_TYPE_APPLICATION = "application"
  REF_TYPE_WEBSITE           = "website"
  REF_TYPE_VCS               = "vcs"
  PURL_GITHUB_PREFIX         = "pkg:github/"

  SCOPE_REQUIRED = "required"
  SCOPE_OPTIONAL = "optional"

  # Regex pattern for extracting owner/repo from GitHub Git URLs
  private GITHUB_REPO_PATTERN = /github\.com[\/:]([^\/]+\/[^\/]+?)(?:\.git)?$/

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
    exit(1) unless validate_options(options)
    exit(1) unless validate_input_files(options)

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
    unless File.file?(options.shard_file)
      STDERR.puts "Error: `#{options.shard_file}` not found."
      return false
    end

    unless File.file?(options.shard_lock_file)
      STDERR.puts "Error: `#{options.shard_lock_file}` not found."
      return false
    end

    true
  end

  # Generates the BOM from input files.
  private def generate_bom(options : Options) : CycloneDX::BOM
    shard = read_yaml_file(options.shard_file, ShardFile)
    main_component = parse_main_component(shard)
    dev_dep_names = shard.dev_dependency_names
    dependencies = parse_dependencies(options.shard_lock_file, dev_dep_names)

    tool = CycloneDX::Tool.new(vendor: "hahwul", name: "cyclonedx-cr", version: VERSION)
    timestamp = Time.utc.to_rfc3339
    metadata = CycloneDX::Metadata.new(component: main_component, tools: [tool], timestamp: timestamp)

    # Build dependency graph
    dep_graph = build_dependency_graph(main_component, dependencies)

    CycloneDX::BOM.new(
      spec_version: options.spec_version,
      metadata: metadata,
      components: dependencies,
      dependencies: dep_graph
    )
  end

  # Writes the BOM output to file or stdout.
  private def write_output(bom : CycloneDX::BOM, options : Options) : Nil
    output_content = serialize_bom(bom, options.output_format)

    if options.output_file.empty?
      puts output_content
    else
      begin
        File.write(options.output_file, output_content)
        STDERR.puts "SBOM successfully written to #{options.output_file} in #{options.output_format.upcase} format."
      rescue ex : File::Error
        STDERR.puts "Error: Could not write to `#{options.output_file}`."
        STDERR.puts ex.message
        exit(1)
      end
    end
  end

  # Serializes the BOM to the specified format.
  private def serialize_bom(bom : CycloneDX::BOM, format : String) : String
    case format
    when "json" then bom.to_json
    when "xml"  then bom.to_xml
    when "csv"  then bom.to_csv
    else             raise "BUG: Unsupported format '#{format}'"
    end
  end

  # Reads and parses a YAML file into the specified type.
  private def read_yaml_file(file_path : String, type : T.class) : T forall T
    File.open(file_path) { |file| T.from_yaml(file) }
  rescue ex : YAML::ParseException
    STDERR.puts "Error: Failed to parse `#{file_path}`. Please ensure the file contains valid YAML."
    STDERR.puts ex.message
    exit(1)
  rescue ex : File::Error
    STDERR.puts "Error: Could not read `#{file_path}`."
    STDERR.puts ex.message
    exit(1)
  end

  # Generates a bom-ref string for a component.
  private def generate_bom_ref(name : String, version : String) : String
    "#{name}@#{version}"
  end

  # Parses the main component information from a parsed ShardFile.
  private def parse_main_component(shard : ShardFile) : CycloneDX::Component
    licenses = shard.license.try { |license| [CycloneDX::License.new(name: license)] }

    external_refs = [
      shard.homepage.try { |url| CycloneDX::ExternalReference.new(ref_type: REF_TYPE_WEBSITE, url: url) },
      shard.repository.try { |url| CycloneDX::ExternalReference.new(ref_type: REF_TYPE_VCS, url: url) },
    ].compact
    external_refs = nil if external_refs.empty?

    author = shard.authors.try(&.first?)

    CycloneDX::Component.new(
      component_type: COMPONENT_TYPE_APPLICATION,
      name: shard.name,
      version: shard.version,
      description: shard.description,
      author: author,
      licenses: licenses,
      external_references: external_refs,
      bom_ref: generate_bom_ref(shard.name, shard.version)
    )
  end

  # Parses dependency components from `shard.lock`.
  private def parse_dependencies(file_path : String, dev_dep_names : Set(String)) : Array(CycloneDX::Component)
    lock_file = read_yaml_file(file_path, ShardLockFile)

    lock_file.shards.map do |name, details|
      scope = dev_dep_names.includes?(name) ? SCOPE_OPTIONAL : SCOPE_REQUIRED

      CycloneDX::Component.new(
        name: name,
        version: details.version,
        purl: generate_purl(details),
        bom_ref: generate_bom_ref(name, details.version),
        scope: scope
      )
    end
  end

  # Builds the dependency graph for the BOM.
  # The main component depends on all listed dependencies.
  # Each dependency has an empty dependsOn list (transitive deps not available from shard.lock).
  private def build_dependency_graph(main_component : CycloneDX::Component,
                                     dependencies : Array(CycloneDX::Component)) : Array(CycloneDX::Dependency)
    dep_refs = dependencies.compact_map(&.bom_ref)

    graph = [] of CycloneDX::Dependency

    # Main component depends on all dependencies
    if main_ref = main_component.bom_ref
      graph << CycloneDX::Dependency.new(ref: main_ref, depends_on: dep_refs)
    end

    # Each dependency listed with empty dependsOn
    dependencies.each do |dep|
      if ref = dep.bom_ref
        graph << CycloneDX::Dependency.new(ref: ref)
      end
    end

    graph
  end

  # Generates a Package URL (PURL) for a given shard based on its details.
  # Currently supports GitHub-based PURLs.
  private def generate_purl(details : ShardLockEntry) : String?
    if github_repo = details.github
      "#{PURL_GITHUB_PREFIX}#{github_repo}@#{details.version}"
    elsif git_url = details.git
      parse_github_repo_from_git_url(git_url).try { |repo| "#{PURL_GITHUB_PREFIX}#{repo}@#{details.version}" }
    end
  end

  # Extracts the GitHub repository path (owner/repo) from a Git URL.
  private def parse_github_repo_from_git_url(git_url : String) : String?
    if git_url =~ GITHUB_REPO_PATTERN
      $1
    end
  end
end
