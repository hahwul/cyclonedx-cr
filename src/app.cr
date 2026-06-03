require "option_parser"
require "uri"
require "spdx"
require "./cyclonedx/bom"
require "./cyclonedx/component"
require "./cyclonedx/models"
require "./cyclonedx/metadata"
require "./shard/shard_file"
require "./shard/shard_lock_file"

# Main application class for generating CycloneDX SBOMs from Crystal Shard files.
# Handles command-line argument parsing, file reading, and SBOM generation.
class App
  VERSION            = "1.3.0"
  SUPPORTED_VERSIONS = CycloneDX::BOM::SUPPORTED_VERSIONS
  SUPPORTED_FORMATS  = ["json", "xml", "csv"]
  DEFAULT_VERSION    = "1.6"
  DEFAULT_FORMAT     = "json"
  DEFAULT_SHARD_FILE = "shard.yml"
  DEFAULT_LOCK_FILE  = "shard.lock"

  COMPONENT_TYPE_APPLICATION = "application"
  REF_TYPE_WEBSITE           = "website"
  REF_TYPE_VCS               = "vcs"
  PURL_GITHUB_PREFIX         = "pkg:github/"
  PURL_GITLAB_PREFIX         = "pkg:gitlab/"
  PURL_BITBUCKET_PREFIX      = "pkg:bitbucket/"

  SCOPE_REQUIRED = "required"
  SCOPE_OPTIONAL = "optional"

  # Regex patterns for extracting owner/repo from Git URLs.
  #
  # The host may be followed by an explicit `:<port>/` (e.g. an
  # `ssh://git@github.com:22/owner/repo` remote); that port must be consumed,
  # not captured as part of the namespace. `(?::\d+\/|[\/:])` matches either a
  # `:port/` or the ordinary `/` (scheme URL) / `:` (scp-form) separator.
  # A trailing `.git` suffix and any trailing slashes are tolerated. GitHub and
  # Bitbucket repos are exactly `owner/repo`; GitLab additionally supports
  # subgroups (`group/subgroup/.../repo`), so its pattern captures the full path.
  private GITHUB_REPO_PATTERN    = /github\.com(?::\d+\/|[\/:])([^\/]+\/[^\/]+?)(?:\.git)?\/*$/
  private GITLAB_REPO_PATTERN    = /gitlab\.com(?::\d+\/|[\/:])([^\/].*?)(?:\.git)?\/*$/
  private BITBUCKET_REPO_PATTERN = /bitbucket\.org(?::\d+\/|[\/:])([^\/]+\/[^\/]+?)(?:\.git)?\/*$/

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
      parser.invalid_option do |flag|
        STDERR.puts "Error: Unknown option '#{flag}'."
        STDERR.puts parser
        exit(1)
      end
      parser.missing_option do |flag|
        STDERR.puts "Error: Missing value for option '#{flag}'."
        STDERR.puts parser
        exit(1)
      end
      parser.unknown_args do |before, after|
        # Unrecognised flags (e.g. `--foo`, `-x`) also appear here, but they are
        # reported by `invalid_option`, so they are filtered out to avoid
        # double-reporting. A bare `-` is NOT routed to `invalid_option`, so it
        # is kept and flagged here; genuine positional arguments (which this tool
        # never accepts) are likewise flagged so a dropped dash like
        # `spec-version 1.5` is not silently ignored.
        positionals = (before + after).reject { |arg| arg.starts_with?('-') && arg != "-" }
        unless positionals.empty?
          STDERR.puts "Error: Unexpected argument(s): #{positionals.join(", ")}. This tool takes options only."
          STDERR.puts parser
          exit(1)
        end
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
    # `YAML::Serializable` raises `YAML::ParseException` both for invalid YAML
    # syntax and for valid YAML that is missing a required attribute. The two
    # cases need different guidance, so distinguish them by the message.
    if (msg = ex.message) && msg.includes?("Missing YAML attribute")
      STDERR.puts "Error: `#{file_path}` is valid YAML but is missing a required field."
    else
      STDERR.puts "Error: Failed to parse `#{file_path}`. Please ensure the file contains valid YAML."
    end
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

  # Simple URL validation pattern (http/https/git schemes)
  private URL_PATTERN = /\A(?:https?:\/\/.+|git:\/\/.+|git@.+)\z/

  # SPDX license expression operators
  private SPDX_EXPRESSION_PATTERN = /\b(AND|OR|WITH)\b/

  # Build a licenses array for a shard.yml license field.
  #
  # - Strings that contain an AND/OR/WITH operator AND parse as a valid SPDX
  #   expression become a LicenseExpression. The validity check matters: a
  #   free-form string like "Free for personal OR commercial use" contains
  #   "OR" but is not a license expression, so it must NOT be emitted as one
  #   (an invalid `expression` fails CycloneDX/SPDX validation).
  # - Single identifiers that exist in the SPDX catalog use the canonical `id`.
  # - Everything else falls back to the free-form `name`.
  private def build_licenses(license : String) : Array(CycloneDX::License | CycloneDX::LicenseExpression)
    if license =~ SPDX_EXPRESSION_PATTERN && Spdx.valid_expression?(license)
      [CycloneDX::LicenseExpression.new(expression: license)] of CycloneDX::License | CycloneDX::LicenseExpression
    elsif Spdx.license?(license)
      canonical = Spdx.find_license(license).id
      [CycloneDX::License.new(id: canonical)] of CycloneDX::License | CycloneDX::LicenseExpression
    else
      [CycloneDX::License.new(name: license)] of CycloneDX::License | CycloneDX::LicenseExpression
    end
  end

  # Parses the main component information from a parsed ShardFile.
  private def parse_main_component(shard : ShardFile) : CycloneDX::Component
    licenses = nil
    shard.license.try do |license|
      licenses = build_licenses(license)
    end

    external_refs = [
      shard.homepage.try { |url| CycloneDX::ExternalReference.new(ref_type: REF_TYPE_WEBSITE, url: url) if url =~ URL_PATTERN },
      shard.repository.try { |url| CycloneDX::ExternalReference.new(ref_type: REF_TYPE_VCS, url: url) if url =~ URL_PATTERN },
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

    lock_file.shards.compact_map do |name, details|
      # A component name is required and must be non-empty; an empty/blank lock
      # key would yield a schema-invalid component, so skip it with a warning.
      if name.blank?
        STDERR.puts "Warning: skipping lock entry with an empty shard name."
        next
      end

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
    graph = [] of CycloneDX::Dependency
    seen = Set(String).new

    main_ref = main_component.bom_ref

    # Main component depends on all dependencies. De-duplicate the refs and drop
    # the main component's own ref so the graph never contains a self-edge (this
    # can happen if a locked dependency shares the project's name@version).
    if main_ref
      dep_refs = dependencies.compact_map(&.bom_ref).reject { |r| r == main_ref }.uniq!
      graph << CycloneDX::Dependency.new(ref: main_ref, depends_on: dep_refs)
      seen << main_ref
    end

    # Each dependency listed once with an empty dependsOn.
    dependencies.each do |dep|
      if ref = dep.bom_ref
        next if seen.includes?(ref)
        seen << ref
        graph << CycloneDX::Dependency.new(ref: ref)
      end
    end

    graph
  end

  # Generates a Package URL (PURL) for a given shard based on its details.
  # Supports GitHub, GitLab and (via Git URL) Bitbucket repositories.
  private def generate_purl(details : ShardLockEntry) : String?
    if github_repo = details.github
      build_purl(PURL_GITHUB_PREFIX, github_repo, details.version, lowercase: true)
    elsif gitlab_repo = details.gitlab
      build_purl(PURL_GITLAB_PREFIX, gitlab_repo, details.version, lowercase: false)
    elsif git_url = details.git
      parse_purl_from_git_url(git_url, details.version)
    end
  end

  # Extracts a PURL from a Git URL by matching known hosts (GitHub, GitLab,
  # Bitbucket). Returns nil for unrecognised hosts.
  private def parse_purl_from_git_url(git_url : String, version : String) : String?
    if git_url =~ GITHUB_REPO_PATTERN
      build_purl(PURL_GITHUB_PREFIX, $1, version, lowercase: true)
    elsif git_url =~ GITLAB_REPO_PATTERN
      build_purl(PURL_GITLAB_PREFIX, $1, version, lowercase: false)
    elsif git_url =~ BITBUCKET_REPO_PATTERN
      build_purl(PURL_BITBUCKET_PREFIX, $1, version, lowercase: true)
    end
  end

  # Assembles a canonical PURL from a repo path ("owner/repo", or for GitLab a
  # longer "group/subgroup/repo") and a version.
  #
  # Per the package-url spec every component is percent-encoded so reserved
  # characters (space, '+', '@', '&', '#', ...) cannot corrupt the PURL grammar.
  # The github and bitbucket types define the namespace/name as case-insensitive
  # and require it lowercased; gitlab paths are case-sensitive and left as-is.
  # The version is always percent-encoded but never case-folded.
  private def build_purl(prefix : String, repo_path : String, version : String, lowercase : Bool) : String
    repo_path = repo_path.downcase if lowercase
    "#{prefix}#{encode_purl_path(repo_path)}@#{encode_purl_segment(version)}"
  end

  # Percent-encodes a single PURL component. `URI.encode_path_segment` leaves
  # exactly the PURL unreserved set (A-Z a-z 0-9 . - _ ~) untouched and encodes
  # everything else, which matches the spec's component encoding rules.
  private def encode_purl_segment(value : String) : String
    URI.encode_path_segment(value)
  end

  # Percent-encodes a "namespace/name" path one slash-delimited segment at a
  # time so the '/' separators are preserved while reserved characters inside
  # each segment are still encoded.
  private def encode_purl_path(path : String) : String
    path.split('/').map { |segment| encode_purl_segment(segment) }.join('/')
  end
end
