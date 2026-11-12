require "option_parser"
require "uri"
require "spdx"
require "./cyclonedx/bom"
require "./cyclonedx/component"
require "./cyclonedx/models"
require "./cyclonedx/metadata"
require "./cyclonedx/validator"
require "./shard/shard_file"
require "./shard/shard_lock_file"

# Main application class for generating CycloneDX SBOMs from Crystal Shard files.
# Handles command-line argument parsing, file reading, and SBOM generation.
class App
  VERSION            = "1.4.0"
  SUPPORTED_VERSIONS = CycloneDX::BOM::SUPPORTED_VERSIONS
  SUPPORTED_FORMATS  = ["json", "xml", "csv"]
  DEFAULT_VERSION    = "1.6"
  DEFAULT_FORMAT     = "json"
  DEFAULT_SHARD_FILE = "shard.yml"
  DEFAULT_LOCK_FILE  = "shard.lock"

  COMPONENT_TYPE_APPLICATION = "application"
  COMPONENT_TYPE_LIBRARY     = "library"
  REF_TYPE_WEBSITE           = "website"
  REF_TYPE_VCS               = "vcs"
  PURL_GITHUB_PREFIX         = "pkg:github/"
  PURL_GITLAB_PREFIX         = "pkg:gitlab/"
  PURL_BITBUCKET_PREFIX      = "pkg:bitbucket/"

  SCOPE_REQUIRED = "required"
  SCOPE_OPTIONAL = "optional"

  # Composition aggregates for the dependency graph. See `build_compositions`.
  COMPOSITION_COMPLETE   = "complete"
  COMPOSITION_INCOMPLETE = "incomplete"
  COMPOSITION_UNKNOWN    = "unknown"

  # Where `shards install` puts dependencies, relative to the project, unless
  # `SHARDS_INSTALL_PATH` says otherwise.
  DEFAULT_INSTALL_DIR = "lib"

  # Where `/dev/stdin` and shell process substitution (`<(...)`) put a pipe.
  private PIPE_DIRS = {"/dev", "/dev/fd", "/proc/self/fd"}

  # The structured `component.authors` array was introduced in 1.6.
  AUTHORS_MIN_VERSION = "1.6"

  # The `metadata.tools` object form (`{components, services}`) was introduced
  # in 1.5, which deprecated the older flat list of tools.
  TOOLS_OBJECT_MIN_VERSION = "1.5"
  TOOL_VENDOR              = "hahwul"
  TOOL_NAME                = "cyclonedx-cr"

  # Under `--reproducible` the two fields that would otherwise change on every
  # run are pinned: the timestamp to the Unix epoch and the serial number to the
  # RFC 4122 nil UUID, which is the conventional "no identity assigned" value.
  REPRODUCIBLE_TIMESTAMP     = "1970-01-01T00:00:00Z"
  REPRODUCIBLE_SERIAL_NUMBER = "urn:uuid:00000000-0000-0000-0000-000000000000"

  # Known forge hosts, matched against the parsed host of a git remote (see
  # `split_git_remote`). Matching the *host* rather than searching the whole URL
  # matters: a substring search treats `notgithub.com/o/r` and a mirror path
  # like `mirror.internal/github.com/o/r` as GitHub, which would attribute the
  # component to an upstream project it does not actually come from.
  # Hosts are compared lowercased because they are case-insensitive (RFC 3986).
  private GITHUB_HOST    = "github.com"
  private GITLAB_HOST    = "gitlab.com"
  private BITBUCKET_HOST = "bitbucket.org"

  # GitHub and Bitbucket repos are exactly `owner/repo`; GitLab additionally
  # supports subgroups (`group/subgroup/.../repo`), so it accepts 2 or more
  # path segments.
  private OWNER_REPO_SEGMENTS = 2

  # The `owner/repo` shorthand resolvers, in the order `generate_purl` tries
  # them, with the PURL type each maps to and whether that type case-folds the
  # namespace/name.
  #
  # `codeberg:` has no registered PURL type, so it produces no PURL — but its
  # repository URL is still recorded as a `vcs` external reference, which is the
  # only identifier available for it.
  private CODEBERG_HOST = "codeberg.org"

  # Base URLs used to reconstruct a browsable repository URL from an
  # `owner/repo` shorthand, so that every dependency carries a `vcs` external
  # reference even when it gets no PURL.
  private FORGE_BASE_URLS = {
    "github"    => "https://github.com/",
    "gitlab"    => "https://gitlab.com/",
    "bitbucket" => "https://bitbucket.org/",
    "codeberg"  => "https://codeberg.org/",
  }

  # Holds parsed command-line options.
  record Options,
    shard_file : String,
    shard_lock_file : String,
    output_file : String,
    spec_version : String,
    output_format : String,
    reproducible : Bool do
    # The BOM serial number to use, or nil to let a random one be generated.
    def serial_number : String?
      REPRODUCIBLE_SERIAL_NUMBER if reproducible
    end
  end

  # Runs the main application logic.
  def run
    options = parse_options
    exit(1) unless validate_options(options)
    exit(1) unless validate_input_files(options)

    bom = generate_bom(options)
    exit(1) unless validate_bom(bom)
    write_output(bom, options)
  end

  # Runs the library validator over the assembled BOM before it is written.
  #
  # `generate_bom` can only produce a structurally-invalid BOM from malformed
  # input — most notably a `shard.yml` whose `name` is present but empty, which
  # yields a component with an empty `name`. Blank names are already rejected
  # for `shard.lock` entries; this closes the same gap for the root component
  # and gives the whole BOM tree a schema safety net. Emitting an invalid SBOM
  # that a downstream consumer rejects later is worse than failing here, so this
  # is a hard error.
  #
  # Spec-version downgrades are reported separately as warnings: the version gate
  # has already made the output valid, and the user asked for the older version,
  # so telling them what that version could not carry is information rather than
  # a failure.
  private def validate_bom(bom : CycloneDX::BOM) : Bool
    validator = CycloneDX::Validator.new
    valid = validator.validate(bom)

    validator.warnings.each do |warning|
      warn(warning.to_s)
    end
    return true if valid

    STDERR.puts "Error: the generated SBOM is not valid CycloneDX:"
    validator.errors.each { |error| STDERR.puts "  - #{error}" }
    false
  end

  # Prints a warning on stderr. Control characters are escaped: the message can
  # carry names from shard.lock and from third-party installed shard.yml files,
  # and a raw newline would let one start a line of its own, which CI runners
  # such as GitHub Actions parse as a workflow command (`::add-mask::...`).
  private def warn(message : String) : Nil
    STDERR.puts "Warning: #{message.gsub(/[[:cntrl:]]/, &.dump_unquoted)}"
  end

  # Parses command-line options and returns an Options record.
  private def parse_options : Options
    shard_file = DEFAULT_SHARD_FILE
    shard_lock_file = DEFAULT_LOCK_FILE
    output_file = ""
    spec_version = DEFAULT_VERSION
    output_format = DEFAULT_FORMAT
    reproducible = false

    OptionParser.parse do |parser|
      parser.banner = "Usage: cyclonedx-cr [arguments]"
      parser.on("-i FILE", "--input=FILE", "shard.lock file path (default: #{DEFAULT_LOCK_FILE})") { |file| shard_lock_file = file }
      parser.on("-s FILE", "--shard=FILE", "shard.yml file path (default: #{DEFAULT_SHARD_FILE})") { |file| shard_file = file }
      parser.on("-o FILE", "--output=FILE", "Output file path (default: stdout)") { |file| output_file = file }
      parser.on("--spec-version VERSION", "CycloneDX spec version (options: #{SUPPORTED_VERSIONS.join(", ")}, default: #{DEFAULT_VERSION})") { |v| spec_version = v }
      parser.on("--output-format FORMAT", "Output format (options: #{SUPPORTED_FORMATS.join(", ")}, default: #{DEFAULT_FORMAT})") { |format| output_format = format.downcase }
      parser.on("--reproducible", "Pin the timestamp and serial number so repeated runs over unchanged inputs (shard.yml, shard.lock, installed lib/) produce identical output") { reproducible = true }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
      # The tool records its own version in `metadata.tools`, so being unable to
      # report it made an emitted SBOM impossible to trace back to a build.
      parser.on("-v", "--version", "Show the version") do
        puts "cyclonedx-cr #{VERSION}"
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
      output_format: output_format,
      reproducible: reproducible
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

  # Validates that required input files exist. Anything readable that is not a
  # directory counts, not just a regular file: `-i /dev/stdin` and a shell
  # process substitution (`-s <(...)`) are pipes.
  private def validate_input_files(options : Options) : Bool
    {options.shard_file, options.shard_lock_file}.all? do |path|
      next true if File.exists?(path) && !File.directory?(path)
      STDERR.puts "Error: `#{path}` not found."
      false
    end
  end

  # Generates the BOM from input files.
  private def generate_bom(options : Options) : CycloneDX::BOM
    shard = read_yaml_file(options.shard_file, ShardFile)
    main_component = parse_main_component(shard, options.spec_version)
    main_ref = generate_bom_ref(shard.name, shard.version)
    locked = locked_shards(options.shard_lock_file, main_ref)

    # `shard.lock` is a flat list: it records what is installed, not which shard
    # required which. The edges come from each installed shard's own shard.yml.
    declared = installed_dependencies(locked, install_path(options.shard_file))
    direct = (shard.runtime_dependency_names | shard.dev_dependency_names).to_a
    optional = dev_only_names(shard, declared)

    refs = locked.to_h { |name, details| {name, generate_bom_ref(name, details.version)} }
    dependencies = locked.map do |name, details|
      build_dependency(name, details, refs[name], optional.includes?(name) ? SCOPE_OPTIONAL : SCOPE_REQUIRED)
    end

    metadata = build_metadata(main_component, options)

    dep_graph, aggregates = build_dependency_graph(shard.name, main_ref, direct, declared, refs)

    CycloneDX::BOM.new(
      spec_version: options.spec_version,
      metadata: metadata,
      components: dependencies,
      dependencies: dep_graph,
      compositions: build_compositions(aggregates),
      serial_number: options.serial_number
    )
  end

  # `metadata`, recording this tool in `tools`. From 1.5 the flat list of tools
  # is deprecated in favour of the `{components, services}` object, so the tool
  # is described as an application component there; 1.4 has only the list. The
  # vendor becomes the component `group`, the mapping the CycloneDX libraries
  # use when converting between the two forms.
  private def build_metadata(main_component : CycloneDX::Component, options : Options) : CycloneDX::Metadata
    legacy = CycloneDX::VersionGate.newer?(TOOLS_OBJECT_MIN_VERSION, options.spec_version)
    CycloneDX::Metadata.new(
      component: main_component, timestamp: bom_timestamp(options),
      tools: (legacy ? [CycloneDX::Tool.new(vendor: TOOL_VENDOR, name: TOOL_NAME, version: VERSION)] : nil),
      tool_components: (legacy ? nil : [CycloneDX::Component.new(name: TOOL_NAME, version: VERSION,
        group: TOOL_VENDOR, component_type: COMPONENT_TYPE_APPLICATION)]))
  end

  # Groups the graph nodes by how much is known about their edges, so a consumer
  # can tell a leaf apart from a shard whose dependencies could not be read.
  # `complete` asserts no further edges exist; `incomplete` that some do (a
  # declared dependency missing from shard.lock); `unknown` that it may be
  # either (the shard's installed shard.yml was unavailable).
  private def build_compositions(aggregates : Hash(String, Array(String))) : Array(CycloneDX::Composition)
    aggregates.map { |aggregate, refs| CycloneDX::Composition.new(aggregate: aggregate, dependencies: refs) }
  end

  # Where `shards install` put the dependencies: `SHARDS_INSTALL_PATH` when set
  # (shards resolves it against the working directory, and so does this),
  # otherwise `lib/` next to shard.yml.
  private def install_path(shard_file : String) : String
    # A piped shard.yml (`-s /dev/stdin`, `-s <(...)`) has no project
    # directory; shards itself installs to `lib/` under the working directory.
    project_dir = File.dirname(shard_file)
    project_dir = "." if project_dir.in?(PIPE_DIRS)
    ENV["SHARDS_INSTALL_PATH"]?.presence || File.join(project_dir, DEFAULT_INSTALL_DIR)
  end

  # name => the runtime dependencies declared by that shard's installed
  # shard.yml, or nil when they are unknown. shards installs only a
  # dependency's `dependencies`, never its `development_dependencies`, so those
  # are its edges.
  private def installed_dependencies(locked : Hash(String, ShardLockEntry), install_dir : String) : Hash(String, Array(String)?)
    declared = {} of String => Array(String)?
    if !locked.empty? && !Dir.exists?(install_dir)
      warn("`#{install_dir}` not found; run `shards install` to record transitive dependencies. Their dependency graph is reported as unknown.")
      locked.each_key { |name| declared[name] = nil }
      return declared
    end

    installed = installed_versions(install_dir)
    locked.each do |name, details|
      declared[name] = installed_shard_dependencies(name, details, install_dir, installed)
    end
    declared
  end

  # The edges of one installed shard, or nil (with a warning) when they cannot
  # be trusted: its shard.yml is unreadable, or shards recorded installing a
  # different version than shard.lock pins (a stale `lib/`, e.g. a CI cache
  # restored from an older lock), whose edges would be the wrong ones.
  private def installed_shard_dependencies(name : String, details : ShardLockEntry, install_dir : String,
                                           installed : Hash(String, ShardLockEntry)) : Array(String)?
    # The name comes from shard.lock; one that is not a single path segment
    # (`../x`, `a/b`) is not a directory shards could have installed to, and a
    # NUL byte cannot be in a path at all.
    if name.matches?(/[\/\\\0]/) || name.in?(".", "..")
      warn("`#{name}` is not a valid shard name; its dependencies are unknown.")
      return
    end
    path = File.join(install_dir, name, DEFAULT_SHARD_FILE)
    if (stale = installed[name]?.try(&.version)) && stale != details.version
      warn("installed `#{name}` is #{stale} but shard.lock pins #{details.version}; run `shards install`. Its dependencies are unknown.")
      return
    end

    File.open(path) { |file| ShardFile.from_yaml(file) }.runtime_dependency_names.to_a
  rescue ex : IO::Error | YAML::ParseException
    warn("could not read `#{path}` (#{ex.message}); the dependencies of `#{name}` are unknown.")
    nil
  end

  # What shards recorded installing (`<install dir>/.shards.info`, same shape as
  # shard.lock), or nothing when that file is absent or unreadable.
  private def installed_versions(install_dir : String) : Hash(String, ShardLockEntry)
    File.open(File.join(install_dir, ".shards.info")) { |file| ShardLockFile.from_yaml(file) }.shards
  rescue IO::Error | YAML::ParseException
    {} of String => ShardLockEntry
  end

  # The locked shards reachable only through `development_dependencies`.
  #
  # Anything a runtime dependency pulls in, directly or transitively, stays
  # required even when a dev dependency also needs it: marking it `optional`
  # would understate its scope and push it down in vulnerability triage. For the
  # same reason a shard is only called dev-only when the runtime side of the
  # graph is fully known. Direct development dependencies are optional either
  # way: shard.yml declares them so, which is what this tool has always reported.
  private def dev_only_names(shard : ShardFile, declared : Hash(String, Array(String)?)) : Set(String)
    runtime, runtime_known = reachable(shard.runtime_dependency_names, declared)
    dev_roots = shard.dev_dependency_names
    dev = runtime_known ? reachable(dev_roots, declared)[0] : dev_roots
    dev - runtime
  end

  # Every shard name reachable from `roots`, and whether every edge on the way
  # was known (each name is locked and its shard.yml was read).
  private def reachable(roots : Set(String), declared : Hash(String, Array(String)?)) : {Set(String), Bool}
    seen = Set(String).new
    known = true
    queue = Deque.new(roots.to_a)
    while name = queue.shift?
      next unless seen.add?(name)
      if deps = declared[name]?
        queue.concat(deps)
      else
        known = false
      end
    end
    {seen, known}
  end

  # The BOM timestamp. Fixed to the Unix epoch under `--reproducible` so two
  # runs over the same inputs produce byte-identical output.
  private def bom_timestamp(options : Options) : String
    return REPRODUCIBLE_TIMESTAMP if options.reproducible
    Time.utc.to_rfc3339
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

  # Generates a bom-ref string for a component. A component with no known
  # version is referenced by name alone rather than by a fabricated
  # `name@unknown`.
  private def generate_bom_ref(name : String, version : String?) : String
    version ? "#{name}@#{version}" : name
  end

  # Simple URL validation pattern (http/https/git/ssh schemes)
  private URL_PATTERN = /\A(?:https?:\/\/.+|git:\/\/.+|ssh:\/\/.+|git@.+)\z/

  # scp-style git remote: `user@host:path` (no scheme). This is NOT a valid URI
  # so it cannot be emitted verbatim as a CycloneDX externalReference `url`
  # (the XSD validates it as `xs:anyURI`). The capture groups are the user, host
  # and path. The `(?!\/)` lookahead skips a `:/...` shape so an already-URI-ish
  # value is left untouched. Only `git@`-form URLs (per `URL_PATTERN`) ever reach
  # this.
  private SCP_GIT_PATTERN = /\A([\w.\-]+)@([\w.\-]+):(?!\/)(.+)\z/

  # `shard.yml` author entries: `Name <email>`, where the name may be absent.
  # The bracketed part must look like an address (`local@domain`, RFC 5322
  # addr-spec): the JSON schemas type `email` as `idn-email`, so `Foo <n/a>`
  # stays a plain name rather than becoming a schema-invalid email.
  private AUTHOR_PATTERN = /\A([^<]*)<\s*([^<>@\s]+@[^<>@\s]+)\s*>\s*\z/

  # Build a licenses array for a shard.yml license field, following the
  # CycloneDX license choice:
  #
  # - A single identifier from the SPDX license list becomes `license.id`. That
  #   is the only form the `id` field (an enum of exactly those ids) accepts.
  # - Anything else that is a valid SPDX expression becomes `expression`. That
  #   covers compound expressions and also single terms that are not a bare
  #   list id: `Apache-2.0+`, `LicenseRef-Foo`, `MIT WITH LLVM-exception`.
  # - Everything else is free text and falls back to `license.name`. Validity
  #   matters here: "Free for personal OR commercial use" contains "OR" but is
  #   no license expression, and an invalid `expression` fails validation.
  #
  # Both the id and the expression are written in canonical form (see
  # `canonical_spdx_expression`), never as the raw shard.yml text.
  private def build_licenses(license : String) : Array(CycloneDX::License | CycloneDX::LicenseExpression)
    expression = canonical_spdx_expression(license)
    choice = if expression.nil?
               CycloneDX::License.new(name: license)
             elsif Spdx.license?(expression)
               CycloneDX::License.new(id: expression)
             else
               CycloneDX::LicenseExpression.new(expression: expression)
             end
    [choice] of CycloneDX::License | CycloneDX::LicenseExpression
  end

  # `license` rewritten as a canonical SPDX expression, or nil when it is not a
  # valid one built from real SPDX license and exception ids.
  #
  # spdx.cr's parser is lenient: it skips surrounding whitespace, takes `and`
  # for `AND`, and only checks the grammar, so a string of
  # bogus ids ("Foo AND Bar") parses too. The CycloneDX `expression` field is "a
  # valid SPDX license expression", so the parse tree is checked and re-rendered
  # instead: ids in their list casing, operators upper case.
  # Deprecated ids are still valid SPDX and are kept.
  private def canonical_spdx_expression(license : String) : String?
    render_spdx(Spdx.parse(license))
  rescue Spdx::ParseError
    nil
  end

  private def render_spdx(node : Spdx::Expression::Node) : String?
    case node
    when Spdx::Expression::LicenseNode
      return unless Spdx.license?(node.id)
      id = Spdx.find_license(node.id).id
      node.or_later? ? "#{id}+" : id
    when Spdx::Expression::LicenseRefNode
      node.to_s
    when Spdx::Expression::WithExceptionNode
      # SPDX allows WITH only after a simple expression, never a group.
      return unless node.license.is_a?(Spdx::Expression::LicenseNode | Spdx::Expression::LicenseRefNode)
      return unless Spdx.exception?(node.exception)
      license = render_spdx(node.license) || return
      "#{license} WITH #{Spdx.find_exception(node.exception).id}"
    when Spdx::Expression::CompoundNode
      left = render_spdx_operand(node.left, node.operator) || return
      right = render_spdx_operand(node.right, node.operator) || return
      "#{left} #{node.operator} #{right}"
    end
  end

  # An operand of `operator`, parenthesised when it is a compound of the other
  # operator. Same-operator chains need none: AND and OR are associative.
  private def render_spdx_operand(node : Spdx::Expression::Node,
                                  operator : Spdx::Expression::CompoundNode::Operator) : String?
    rendered = render_spdx(node) || return
    node.is_a?(Spdx::Expression::CompoundNode) && node.operator != operator ? "(#{rendered})" : rendered
  end

  # Parses the main component information from a parsed ShardFile.
  #
  # `spec_version` is needed because the structured `authors` array only exists
  # from 1.6. The version gate would strip it from an older document anyway, but
  # it would also report the loss — and a warning on every 1.4/1.5 run about a
  # field the user never asked for is just noise.
  private def parse_main_component(shard : ShardFile, spec_version : String) : CycloneDX::Component
    licenses = nil
    shard.license.try do |license|
      licenses = build_licenses(license)
    end

    external_refs = [
      build_external_reference(REF_TYPE_WEBSITE, shard.homepage),
      build_external_reference(REF_TYPE_VCS, shard.repository),
    ].compact
    external_refs = nil if external_refs.empty?

    author = shard.authors.try(&.first?)

    CycloneDX::Component.new(
      component_type: root_component_type(shard),
      name: shard.name,
      version: shard.version,
      description: shard.description,
      author: author,
      authors: shard_authors(shard, spec_version),
      licenses: licenses,
      external_references: external_refs,
      bom_ref: generate_bom_ref(shard.name, shard.version)
    )
  end

  # A shard that declares `targets:` builds executables and is an application;
  # one that does not is a library other shards depend on. Reporting every
  # project as an application mislabels the majority of published shards.
  private def root_component_type(shard : ShardFile) : String
    shard.targets? ? COMPONENT_TYPE_APPLICATION : COMPONENT_TYPE_LIBRARY
  end

  # `shard.yml` authors are free-form `Name <email>` strings. The deprecated
  # single `author` field can only hold the first one, so from 1.6 the full list
  # is also emitted as the structured `authors` array.
  private def shard_authors(shard : ShardFile,
                            spec_version : String) : Array(CycloneDX::OrganizationalContact)?
    return if CycloneDX::VersionGate.newer?(AUTHORS_MIN_VERSION, spec_version)
    authors = shard.authors
    return if authors.nil? || authors.empty?
    authors.map { |author| parse_author(author) }
  end

  # Splits `Name <email>` into its parts. A string with no angle-bracketed
  # address becomes a bare name.
  private def parse_author(author : String) : CycloneDX::OrganizationalContact
    if m = author.match(AUTHOR_PATTERN)
      name = m[1].strip
      CycloneDX::OrganizationalContact.new(
        name: name.empty? ? nil : name, email: m[2].strip)
    else
      CycloneDX::OrganizationalContact.new(name: author.strip)
    end
  end

  # Builds an external reference for a shard.yml URL field, or nil when the URL
  # is missing, not a recognised http/https/git/ssh form, or cannot be cleaned
  # (see `normalize_url`).
  private def build_external_reference(ref_type : String, url : String?) : CycloneDX::ExternalReference?
    return unless url && url =~ URL_PATTERN
    vcs = ref_type == REF_TYPE_VCS
    normalized = normalize_url(url, vcs) || return
    # A remote's query or fragment means nothing to git, but `?private_token=`
    # is a way to authenticate, so neither is published. A website keeps them.
    normalized = strip_url_query_fragment(normalized) if vcs
    CycloneDX::ExternalReference.new(ref_type: ref_type, url: normalized)
  end

  # Rewrites an scp-style git remote (`git@host:owner/repo.git`) to its
  # equivalent `ssh://git@host/owner/repo.git` URI so the value is a valid
  # CycloneDX externalReference `url`.
  #
  # Credentials are dropped: a private dependency is often declared as
  # `https://<token>@host/...` or `https://user:<token>@host/...`, shard.lock
  # keeps that URL verbatim, and an SBOM is a document meant to be published.
  # Over ssh the user is the account to log in as (`git@`), not a secret, so
  # only a password is removed there.
  #
  # nil when the URL cannot be parsed (a bad port), or when an `@` is left
  # outside the userinfo once it is parsed: the parser ends the userinfo at the
  # first `@`, and the authority at the first `/`, `?` or `#`, so a secret
  # holding one of those (`user:p@ss@host`, `https://ab/cd@host`) would be
  # emitted as the host or path. A `remote` (a vcs URL) has no other use for an
  # `@`; a website path can (`https://medium.com/@user`), so only its host is
  # checked.
  private def normalize_url(url : String, remote : Bool) : String?
    if m = url.match(SCP_GIT_PATTERN)
      url = "ssh://#{m[1]}@#{m[2]}/#{m[3]}"
    end

    uri = URI.parse(url)
    rest = remote ? {uri.host, uri.path, uri.query, uri.fragment} : {uri.host}
    return if rest.any?(&.try(&.includes?('@')))
    return url unless uri.user || uri.password
    uri.password = nil
    uri.user = nil unless uri.scheme == "ssh"
    uri.to_s
  rescue URI::Error | OverflowError # a port too big for Int32
    nil
  end

  # Reads the locked shards from `shard.lock`, dropping entries that cannot
  # become a valid component.
  #
  # A component name is required and must be non-empty, so a blank lock key is
  # skipped. An entry whose bom-ref equals the root component's is skipped too:
  # the root lives in `metadata.component`, and a second component under the
  # same bom-ref violates the CycloneDX uniqueness constraint (the XSD enforces
  # it) and is semantically a self-reference. That happens when a `shard.lock`
  # re-lists the project itself, or a dependency shares its exact name@version.
  private def locked_shards(file_path : String, main_ref : String) : Hash(String, ShardLockEntry)
    lock_file = read_yaml_file(file_path, ShardLockFile)

    lock_file.shards.reject do |name, details|
      if name.blank?
        warn("skipping lock entry with an empty shard name.")
        true
      elsif generate_bom_ref(name, details.version) == main_ref
        warn("skipping lock entry that duplicates the root component ref '#{main_ref}'.")
        true
      else
        false
      end
    end
  end

  # Builds the component for one locked shard.
  private def build_dependency(name : String, details : ShardLockEntry, ref : String, scope : String) : CycloneDX::Component
    CycloneDX::Component.new(
      name: name,
      version: details.version,
      purl: generate_purl(details),
      bom_ref: ref,
      scope: scope,
      external_references: dependency_external_refs(details)
    )
  end

  # Records where a locked dependency came from.
  #
  # `shard.lock` always names the source, but only GitHub/GitLab/Bitbucket map to
  # a PURL type. Without this, a Mercurial, Fossil, Codeberg or plain-git
  # dependency ended up with no identifier of any kind — the URL was parsed,
  # found not to match a known forge, and thrown away. A `vcs` reference keeps it.
  private def dependency_external_refs(details : ShardLockEntry) : Array(CycloneDX::ExternalReference)?
    url = source_url(details)
    return unless url
    ref = build_external_reference(REF_TYPE_VCS, url)
    ref ? [ref] : nil
  end

  # The repository URL for a lock entry, reconstructed from the `owner/repo`
  # shorthand resolvers or taken verbatim from the URL-based ones. `path:`
  # dependencies have no remote URL at all.
  private def source_url(details : ShardLockEntry) : String?
    FORGE_BASE_URLS.each do |forge, base|
      shorthand =
        case forge
        when "github"    then details.github
        when "gitlab"    then details.gitlab
        when "bitbucket" then details.bitbucket
        when "codeberg"  then details.codeberg
        end
      next unless shorthand
      path = clean_repo_path(shorthand, OWNER_REPO_SEGMENTS)
      return path ? "#{base}#{path}" : nil
    end

    details.git || details.hg || details.fossil
  end

  # Builds the dependency graph and, per node, the composition aggregate that
  # describes how complete its edges are (see `build_compositions`).
  #
  # The root's edges are its direct dependencies from shard.yml; each locked
  # shard's are the ones its installed shard.yml declares. A shard whose
  # shard.yml could not be read is left out of the graph: the spec reads a
  # component absent from the graph as having unknown dependencies, while an
  # empty `dependsOn` asserts it has none.
  #
  # A dependency may depend back on the root project (a spec helper for it, say),
  # so the root's name resolves to its ref too unless a locked shard claims it.
  private def build_dependency_graph(main_name : String, main_ref : String, direct : Array(String),
                                     declared : Hash(String, Array(String)?),
                                     refs : Hash(String, String)) : {Array(CycloneDX::Dependency), Hash(String, Array(String))}
    graph = [] of CycloneDX::Dependency
    # aggregate => refs, in the order the compositions are emitted.
    aggregates = {COMPOSITION_COMPLETE, COMPOSITION_INCOMPLETE, COMPOSITION_UNKNOWN}.to_h { |aggregate| {aggregate, [] of String} }
    lookup = {main_name => main_ref}.merge(refs)

    nodes = [{main_ref, direct}] of {String, Array(String)?}
    refs.each { |name, ref| nodes << {ref, declared[name]?} }

    nodes.each do |(ref, deps)|
      unless deps
        aggregates[COMPOSITION_UNKNOWN] << ref
        next
      end

      missing = deps.reject { |dep| lookup.has_key?(dep) }
      missing.each do |dep|
        warn("`#{ref}` depends on `#{dep}`, which is not in shard.lock.")
      end
      aggregates[missing.empty? ? COMPOSITION_COMPLETE : COMPOSITION_INCOMPLETE] << ref

      # A shard listing itself is not an edge.
      depends_on = deps.compact_map { |dep| lookup[dep]? }.reject(ref).uniq!
      graph << CycloneDX::Dependency.new(ref: ref, depends_on: depends_on)
    end

    {graph, aggregates.reject { |_, group| group.empty? }}
  end

  # Generates a Package URL (PURL) for a given shard based on its details.
  #
  # Covers the `github:`, `gitlab:` and `bitbucket:` shorthands as well as a
  # `git:` URL pointing at one of those forges. The remaining shards resolvers
  # (`codeberg:`, `hg:`, `fossil:`, `path:`) have no registered PURL type, so
  # they get none — `dependency_external_refs` records their source URL instead.
  private def generate_purl(details : ShardLockEntry) : String?
    version = purl_version(details)

    if github_repo = details.github
      repo = shorthand_repo_path(github_repo, OWNER_REPO_SEGMENTS, OWNER_REPO_SEGMENTS)
      build_purl(PURL_GITHUB_PREFIX, repo, version, lowercase: true) if repo
    elsif gitlab_repo = details.gitlab
      repo = shorthand_repo_path(gitlab_repo, OWNER_REPO_SEGMENTS)
      build_purl(PURL_GITLAB_PREFIX, repo, version, lowercase: false) if repo
    elsif bitbucket_repo = details.bitbucket
      repo = shorthand_repo_path(bitbucket_repo, OWNER_REPO_SEGMENTS, OWNER_REPO_SEGMENTS)
      build_purl(PURL_BITBUCKET_PREFIX, repo, version, lowercase: true) if repo
    elsif git_url = details.git
      parse_purl_from_git_url(git_url, version)
    end
  end

  # The version to put in a forge PURL.
  #
  # `pkg:github`, `pkg:gitlab` and `pkg:bitbucket` define the version as a tag or
  # a commit. shards records `X.Y.Z+git.commit.<sha>` when the locked commit is
  # not a released tag, and that composite string resolves to neither, so the
  # embedded SHA is used instead. A plain `X.Y.Z` names the release, and shards
  # only ever installs a release from the tag `vX.Y.Z` (its git resolver maps a
  # version to `GitTagRef.new "v#{version}"`), so that is the tag the PURL names.
  # The forges do not resolve `X.Y.Z` to `vX.Y.Z`: the bare form is a 404.
  #
  # A `version: 1.0` lock file may instead name the reference directly; an
  # explicit `tag:` is the literal tag, so it wins over the one derived from
  # `version`. `branch:` is never used: a branch name is neither a tag nor a
  # commit, and it identifies a moving target rather than the tree that
  # was actually installed.
  private def purl_version(details : ShardLockEntry) : String?
    details.commit || details.tag || details.version.try { |version| release_tag(version) }
  end

  # The tag shards installs `version` from. A `+` means build metadata the
  # commit pattern did not recognise; that string is no release, so it is kept
  # as it is rather than turned into a tag name that cannot exist.
  private def release_tag(version : String) : String
    version.includes?('+') ? version : "v#{version}"
  end

  # Cleans a `github:`/`gitlab:` shorthand value from `shard.lock`. shards only
  # ever accepts a plain `namespace/name` here, so a value carrying a scheme, a
  # host or stray slashes is malformed and previously got folded verbatim into
  # the PURL (`github: https://github.com/o/r` produced
  # `pkg:github/https%3A//github.com/o/r@1.0`). A malformed PURL is worse than
  # an absent one, so such entries get no PURL and a warning instead.
  private def shorthand_repo_path(value : String, min_segments : Int32,
                                  max_segments : Int32 = Int32::MAX) : String?
    path = clean_repo_path(value, min_segments, max_segments)
    warn("skipping PURL for malformed repository shorthand '#{value}'.") unless path
    path
  end

  # Extracts a PURL from a Git URL by matching known hosts (GitHub, GitLab,
  # Bitbucket). Returns nil for unrecognised hosts or unrecognised URL shapes.
  private def parse_purl_from_git_url(git_url : String, version : String?) : String?
    host, path = split_git_remote(strip_url_query_fragment(git_url)) || return

    case host
    when GITHUB_HOST
      repo = clean_repo_path(path, OWNER_REPO_SEGMENTS, OWNER_REPO_SEGMENTS)
      build_purl(PURL_GITHUB_PREFIX, repo, version, lowercase: true) if repo
    when GITLAB_HOST
      repo = clean_repo_path(path, OWNER_REPO_SEGMENTS)
      build_purl(PURL_GITLAB_PREFIX, repo, version, lowercase: false) if repo
    when BITBUCKET_HOST
      repo = clean_repo_path(path, OWNER_REPO_SEGMENTS, OWNER_REPO_SEGMENTS)
      build_purl(PURL_BITBUCKET_PREFIX, repo, version, lowercase: true) if repo
    end
  end

  # Splits a git remote into its `{host, path}`, or nil when the remote is not a
  # shape we recognise. Two forms are accepted:
  #
  #   * a scheme URI  — `https://host[:port]/path`, `ssh://git@host/path`, `git://host/path`
  #   * an scp remote — `git@host:path`
  #
  # The host is lowercased (hosts are case-insensitive), and any userinfo/port is
  # discarded by the parse rather than being matched as part of the host, so
  # `https://github.com@evil.example/o/r` correctly resolves to `evil.example`.
  private def split_git_remote(url : String) : {String, String}?
    if m = url.match(SCP_GIT_PATTERN)
      return {m[2].downcase, m[3]}
    end

    uri = URI.parse(url)
    host = uri.host
    return if host.nil? || host.empty?
    {host.downcase, uri.path}
  rescue URI::Error | OverflowError # a port too big for Int32
    nil
  end

  # Normalises a repository path ("namespace/name", or for GitLab a longer
  # "group/subgroup/name"): drops surrounding slashes and a trailing `.git`,
  # then returns it only when every slash-delimited segment is non-empty and the
  # segment count falls within `min_segments..max_segments`. Anything else is
  # malformed and yields nil so no PURL is emitted.
  private def clean_repo_path(path : String, min_segments : Int32,
                              max_segments : Int32 = Int32::MAX) : String?
    path = path.strip('/')
    path = path.rchop(".git").strip('/') if path.ends_with?(".git")
    return if path.empty?

    segments = path.split('/')
    return unless min_segments <= segments.size <= max_segments
    return if segments.any?(&.empty?)
    path
  end

  # Strips any `?query` or `#fragment` from a git URL before host/path
  # extraction. Without this, a URL like `https://github.com/o/r.git?ref=main`
  # leaks `?ref=main` into the PURL name (`r.git%3Fref%3Dmain`), leaves the
  # `.git` suffix unstripped, and a `.git/?x=1` form fails to match at all. The
  # earliest of `?` or `#` (and everything after it) is removed.
  private def strip_url_query_fragment(url : String) : String
    url.partition('?')[0].partition('#')[0]
  end

  # Assembles a canonical PURL from a repo path ("owner/repo", or for GitLab a
  # longer "group/subgroup/repo") and a version.
  #
  # Per the package-url spec every component is percent-encoded so reserved
  # characters (space, '+', '@', '&', '#', ...) cannot corrupt the PURL grammar.
  # The github and bitbucket types define the namespace/name as case-insensitive
  # and require it lowercased; gitlab paths are case-sensitive and left as-is.
  # The version is always percent-encoded but never case-folded.
  #
  # A lock entry with no version of its own (e.g. a `path:` dependency) yields a
  # nil version. The package-url encoding for "version not known" is to omit the
  # `@version` component entirely rather than to assert one.
  private def build_purl(prefix : String, repo_path : String, version : String?, lowercase : Bool) : String
    repo_path = repo_path.downcase if lowercase
    purl = "#{prefix}#{encode_purl_path(repo_path)}"
    return purl if version.nil? || version.empty?
    "#{purl}@#{encode_purl_segment(version)}"
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
