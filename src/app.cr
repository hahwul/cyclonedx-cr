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

  # `shard.lock` cannot express transitive edges, so the dependency graph is
  # always declared incomplete. See `build_compositions`.
  COMPOSITION_INCOMPLETE = "incomplete"

  # The structured `component.authors` array was introduced in 1.6.
  AUTHORS_MIN_VERSION = "1.6"

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
      STDERR.puts "Warning: #{warning}"
    end
    return true if valid

    STDERR.puts "Error: the generated SBOM is not valid CycloneDX:"
    validator.errors.each { |error| STDERR.puts "  - #{error}" }
    false
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
      parser.on("--reproducible", "Pin the timestamp and serial number so repeated runs over unchanged inputs produce identical output") { reproducible = true }
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
    main_component = parse_main_component(shard, options.spec_version)
    # A shard may be declared in BOTH `dependencies` and
    # `development_dependencies`. It is still required at runtime, so runtime
    # membership wins: marking such a component `optional` understates its
    # scope and pushes a genuinely runtime-reachable component down in
    # downstream vulnerability triage.
    dev_dep_names = shard.dev_dependency_names - shard.runtime_dependency_names
    dependencies = parse_dependencies(options.shard_lock_file, dev_dep_names)
    dependencies = drop_root_collisions(dependencies, main_component.bom_ref)

    tool = CycloneDX::Tool.new(vendor: "hahwul", name: "cyclonedx-cr", version: VERSION)
    metadata = CycloneDX::Metadata.new(
      component: main_component, tools: [tool], timestamp: bom_timestamp(options))

    # Build dependency graph
    dep_graph = build_dependency_graph(main_component, dependencies)

    CycloneDX::BOM.new(
      spec_version: options.spec_version,
      metadata: metadata,
      components: dependencies,
      dependencies: dep_graph,
      compositions: build_compositions(main_component, dependencies),
      serial_number: options.serial_number
    )
  end

  # `shard.lock` is a flat list of resolved shards: it records *what* is
  # installed but not which shard required which. The dependency graph therefore
  # only knows the root's direct edges, and every other node is listed with no
  # `dependsOn`.
  #
  # Left unqualified, a consumer cannot tell that apart from a genuinely complete
  # graph of leaf dependencies. `compositions` is how CycloneDX expresses the
  # difference, so the whole assembly is declared `incomplete`.
  private def build_compositions(main_component : CycloneDX::Component,
                                 dependencies : Array(CycloneDX::Component)) : Array(CycloneDX::Composition)?
    refs = [] of String
    main_component.bom_ref.try { |ref| refs << ref }
    dependencies.each { |dep| dep.bom_ref.try { |ref| refs << ref } }
    return if refs.empty?

    [CycloneDX::Composition.new(
      aggregate: COMPOSITION_INCOMPLETE,
      dependencies: refs,
    )]
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

  # Simple URL validation pattern (http/https/git schemes)
  private URL_PATTERN = /\A(?:https?:\/\/.+|git:\/\/.+|git@.+)\z/

  # scp-style git remote: `user@host:path` (no scheme). This is NOT a valid URI
  # so it cannot be emitted verbatim as a CycloneDX externalReference `url`
  # (the XSD validates it as `xs:anyURI`). The capture groups are the user, host
  # and path. The `(?!\/)` lookahead skips a `:/...` shape so an already-URI-ish
  # value is left untouched. Only `git@`-form URLs (per `URL_PATTERN`) ever reach
  # this; `ssh://...` remotes are not emitted as external references at all.
  private SCP_GIT_PATTERN = /\A([\w.\-]+)@([\w.\-]+):(?!\/)(.+)\z/

  # SPDX license expression operators
  private SPDX_EXPRESSION_PATTERN = /\b(AND|OR|WITH)\b/

  # `shard.yml` author entries: `Name <email>`, where the name may be absent.
  private AUTHOR_PATTERN = /\A([^<]*)<([^>]+)>\s*\z/

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
    if license =~ SPDX_EXPRESSION_PATTERN && valid_spdx_expression?(license)
      [CycloneDX::LicenseExpression.new(expression: license)] of CycloneDX::License | CycloneDX::LicenseExpression
    elsif Spdx.license?(license)
      canonical = Spdx.find_license(license).id
      [CycloneDX::License.new(id: canonical)] of CycloneDX::License | CycloneDX::LicenseExpression
    else
      [CycloneDX::License.new(name: license)] of CycloneDX::License | CycloneDX::LicenseExpression
    end
  end

  # True when `license` is a SPDX license expression that is both grammatically
  # valid AND built entirely from real SPDX license/exception identifiers.
  #
  # `Spdx.valid_expression?` only checks the grammar, so a well-shaped string of
  # bogus identifiers ("Foo AND Bar", "MIT WITH Bogus-Exception") passes it. The
  # CycloneDX `expression` field is defined as "a valid SPDX license
  # expression", so such strings must fall through to the free-form `name`
  # branch instead of being emitted as an expression. Deprecated ids and
  # non-canonical casing are still valid expressions (they emit a non-"Unknown"
  # warning), so they are intentionally accepted.
  private def valid_spdx_expression?(license : String) : Bool
    return false unless Spdx.valid_expression?(license)
    Spdx.validate_expression(license).warnings.none?(&.starts_with?("Unknown"))
  rescue Spdx::ParseError
    false
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
  # is missing or not a recognised http/https/git form. The URL is normalised so
  # the emitted `url` is always a valid URI (see `normalize_url`).
  private def build_external_reference(ref_type : String, url : String?) : CycloneDX::ExternalReference?
    return unless url && url =~ URL_PATTERN
    CycloneDX::ExternalReference.new(ref_type: ref_type, url: normalize_url(url))
  end

  # Rewrites an scp-style git remote (`git@host:owner/repo.git`) to its
  # equivalent `ssh://git@host/owner/repo.git` URI so the value is a valid
  # CycloneDX externalReference `url`. All other URLs are returned unchanged.
  private def normalize_url(url : String) : String
    if m = url.match(SCP_GIT_PATTERN)
      "ssh://#{m[1]}@#{m[2]}/#{m[3]}"
    else
      url
    end
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
        scope: scope,
        external_references: dependency_external_refs(details)
      )
    end
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

  # Drops any locked dependency whose bom-ref equals the root component's
  # bom-ref. The root component lives in `metadata.component`; emitting a second
  # component in the `components` array under the same bom-ref produces a
  # duplicate identifier, which violates the CycloneDX bom-ref uniqueness
  # constraint (the XSD enforces it) and is semantically a self-reference. This
  # happens when a `shard.lock` re-lists the project itself, or when a
  # dependency coincidentally shares the project's exact name@version.
  private def drop_root_collisions(dependencies : Array(CycloneDX::Component),
                                   main_ref : String?) : Array(CycloneDX::Component)
    return dependencies unless main_ref
    kept = dependencies.reject(&.bom_ref.== main_ref)
    if kept.size < dependencies.size
      STDERR.puts "Warning: skipping lock entry that duplicates the root component ref '#{main_ref}'."
    end
    kept
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
  # embedded SHA is used instead. A plain `X.Y.Z` is left alone; it is the tag
  # (modulo a `v` prefix, which the forges resolve either way).
  private def purl_version(details : ShardLockEntry) : String?
    details.commit || details.version
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
    STDERR.puts "Warning: skipping PURL for malformed repository shorthand '#{value}'." unless path
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
  rescue URI::Error
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
