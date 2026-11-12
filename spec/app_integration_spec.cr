require "spec"
require "json"
require "../src/app"
require "../src/cyclonedx/bom"
require "./support/schema_validation"

BINARY   = "bin/cyclonedx-cr"
FIXTURES = "spec/fixtures"

# Every example below runs the *compiled* binary rather than the library, so a
# missing or stale `bin/cyclonedx-cr` makes them report a dozen failures that
# describe the previous build instead of the working tree — which reads exactly
# like a real regression. Check it up front and say what to do instead. CI builds
# before running the suite, so this never fires there.
private def assert_binary_is_current!
  unless File.exists?(BINARY)
    abort "#{BINARY} is missing; run `shards build` before `crystal spec`."
  end

  built_at = File.info(BINARY).modification_time
  newest = Dir.glob("src/**/*.cr").max_of? { |path| File.info(path).modification_time }
  return unless newest && newest > built_at

  abort "#{BINARY} is older than src/; run `shards build` before `crystal spec`."
end

assert_binary_is_current!

# Every example spawns the binary, which honours `SHARDS_INSTALL_PATH`; one set
# in the developer's or CI environment would redirect the fixtures' `lib/`.
ENV.delete("SHARDS_INSTALL_PATH")

# Runs the binary against the PURL-canonicalization fixture and returns a
# name => purl map for the emitted components.
private def canon_purls : Hash(String, String)
  purls_for("#{FIXTURES}/purl_canon_lock.lock")
end

# Same, for the look-alike/mirror/uppercase forge-host fixture.
private def foreign_purls : Hash(String, String)
  purls_for("#{FIXTURES}/foreign_host_lock.lock")
end

# Same, for the malformed `github:`/`gitlab:` shorthand fixture.
private def shorthand_purls : Hash(String, String)
  purls_for("#{FIXTURES}/shorthand_lock.lock")
end

# Runs the binary against a lock fixture and returns a name => purl map for the
# emitted components. Components without a PURL are simply absent from the map.
# Warning lines are stripped so fixtures that intentionally trip a warning still
# yield parseable JSON.
private def purls_for(lock : String) : Hash(String, String)
  output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{lock} 2>&1`
  json = output.lines.reject(&.starts_with?("Warning")).join("\n")
  result = {} of String => String
  JSON.parse(json)["components"].as_a.each do |c|
    if purl = c["purl"]?
      result[c["name"].as_s] = purl.as_s
    end
  end
  result
end

GRAPH = "#{FIXTURES}/graph"

# Runs the binary over the dependency-graph fixture with `SHARDS_INSTALL_PATH`
# set to `install` (nil unsets it, so the default `lib/` beside shard.yml is
# used). Returns {stdout, stderr}; stderr is kept apart so warnings can be
# asserted on without corrupting the document.
private def run_graph(install : String? = nil, extra = [] of String) : {String, String}
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  args = ["-s", "#{GRAPH}/shard.yml", "-i", "#{GRAPH}/shard.lock", "--reproducible"] + extra
  status = Process.run(BINARY, args, env: {"SHARDS_INSTALL_PATH" => install}, output: stdout, error: stderr)
  status.success?.should be_true
  {stdout.to_s, stderr.to_s}
end

# ref => dependsOn, for a graph BOM.
private def edges(bom : JSON::Any) : Hash(String, Array(String))
  bom["dependencies"].as_a.to_h { |d| {d["ref"].as_s, d["dependsOn"].as_a.map(&.as_s)} }
end

# aggregate => refs, for a graph BOM.
private def aggregates(bom : JSON::Any) : Hash(String, Array(String))
  bom["compositions"].as_a.to_h { |c| {c["aggregate"].as_s, c["dependencies"].as_a.map(&.as_s)} }
end

private def scopes(bom : JSON::Any) : Hash(String, String)
  bom["components"].as_a.to_h { |c| {c["name"].as_s, c["scope"].as_s} }
end

# name => component, for the fixture exercising every shards resolver.
private def all_resolver_components : Hash(String, JSON::Any)
  output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/all_resolvers_lock.lock 2>/dev/null`
  components = {} of String => JSON::Any
  JSON.parse(output)["components"].as_a.each { |c| components[c["name"].as_s] = c }
  components
end

describe "App Integration" do
  describe "CLI argument parsing" do
    it "shows help with -h" do
      output = `#{BINARY} -h 2>&1`
      output.should contain("Usage: cyclonedx-cr")
      $?.success?.should be_true
    end

    it "reports its version with --version and -v" do
      # The version it prints is the one it stamps into `metadata.tools`.
      %w[--version -v].each do |flag|
        output = `#{BINARY} #{flag} 2>&1`
        output.strip.should eq("cyclonedx-cr #{App::VERSION}")
        $?.success?.should be_true
      end
    end

    it "records itself in the legacy tools list for 1.4 and the tools object from 1.5" do
      base = "-s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --reproducible"
      tools = JSON.parse(`#{BINARY} #{base} --spec-version 1.4 2>/dev/null`)["metadata"]["tools"]
      tools.should eq(JSON.parse(%([{"vendor":"hahwul","name":"cyclonedx-cr","version":"#{App::VERSION}"}])))

      %w[1.5 1.6 1.7].each do |version|
        tools = JSON.parse(`#{BINARY} #{base} --spec-version #{version} 2>/dev/null`)["metadata"]["tools"]
        tools.should eq(JSON.parse(%({"components":[{"type":"application","group":"hahwul",) +
                                   %("name":"cyclonedx-cr","version":"#{App::VERSION}"}]})))
        xml = `#{BINARY} #{base} --spec-version #{version} --output-format xml 2>/dev/null`
        xml.should contain(%(<tools><components><component type="application"><group>hahwul</group>))
      end
    end

    it "rejects unknown options" do
      output = `#{BINARY} --unknown 2>&1`
      output.should contain("Unknown option")
      $?.success?.should be_false
    end

    it "rejects unsupported spec version" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --spec-version 9.9 2>&1`
      output.should contain("Unsupported spec version")
      $?.success?.should be_false
    end

    it "rejects unsupported output format" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --output-format yaml 2>&1`
      output.should contain("Unsupported output format")
      $?.success?.should be_false
    end
  end

  describe "input file validation" do
    it "errors when shard.yml is missing" do
      output = `#{BINARY} -s nonexistent.yml -i #{FIXTURES}/shard.lock 2>&1`
      output.should contain("not found")
      $?.success?.should be_false
    end

    it "errors when shard.lock is missing" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i nonexistent.lock 2>&1`
      output.should contain("not found")
      $?.success?.should be_false
    end

    it "reports a YAML syntax error accurately for malformed YAML" do
      output = `#{BINARY} -s #{FIXTURES}/invalid_syntax_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_false
      output.should contain("ensure the file contains valid YAML")
      output.should_not contain("missing a required field")
    end

    it "reports a missing required field without claiming the YAML is invalid" do
      # missing_name_shard.yml is valid YAML but omits the required `name`.
      output = `#{BINARY} -s #{FIXTURES}/missing_name_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_false
      output.should contain("missing a required field")
      output.should_not contain("ensure the file contains valid YAML")
    end
  end

  describe "JSON output" do
    it "generates valid JSON BOM" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      $?.success?.should be_true

      bom = JSON.parse(output)
      bom["bomFormat"].should eq("CycloneDX")
      bom["specVersion"].should eq("1.6")
    end

    it "includes main component in metadata" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      metadata = JSON.parse(output)["metadata"]

      component = metadata["component"]
      component["name"].should eq("test-app")
      component["version"].should eq("0.1.0")
      component["type"].should eq("application")
      component["author"].should eq("Test Author <test@example.com>")
    end

    it "includes licenses from shard.yml as a wrapped SPDX id" do
      # MIT is in the SPDX license list, so it should serialize as
      # `{"license":{"id":"MIT"}}` per CycloneDX 1.6 LicenseChoice.
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      component = JSON.parse(output)["metadata"]["component"]
      licenses = component["licenses"].as_a
      licenses.size.should eq(1)
      licenses[0]["license"]["id"].should eq("MIT")
    end

    it "includes dependencies as components" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a
      components.size.should eq(2)

      names = components.map(&.["name"].as_s)
      names.should contain("kemal")
      names.should contain("ameba")
    end

    it "sets correct scope for dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      kemal = components.find! { |c| c["name"] == "kemal" }
      kemal["scope"].should eq("required")

      ameba = components.find! { |c| c["name"] == "ameba" }
      ameba["scope"].should eq("optional")
    end

    it "generates PURL for github dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      kemal = components.find! { |c| c["name"] == "kemal" }
      kemal["purl"].should eq("pkg:github/kemalcr/kemal@v1.4.0")
    end

    it "generates PURL for git URL dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      ameba = components.find! { |c| c["name"] == "ameba" }
      ameba["purl"].should eq("pkg:github/crystal-ameba/ameba@v1.6.4")
    end

    it "generates dependency graph" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      deps = JSON.parse(output)["dependencies"].as_a

      main_dep = deps.find!(&.["ref"].as_s.starts_with?("test-app@"))
      main_dep["dependsOn"].as_a.size.should eq(2)
    end

    it "respects --spec-version flag" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --spec-version 1.4 2>&1`
      bom = JSON.parse(output)
      bom["specVersion"].should eq("1.4")
    end
  end

  describe "XML output" do
    it "generates valid XML BOM" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --output-format xml 2>&1`
      $?.success?.should be_true
      output.should contain("xmlns=\"http://cyclonedx.org/schema/bom/1.6\"")
      output.should contain("<name>test-app</name>")
    end
  end

  describe "CSV output" do
    it "generates CSV with header, root component, and dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --output-format csv 2>&1`
      $?.success?.should be_true
      lines = output.strip.split("\n")
      lines[0].should eq("Name,Version,PURL,Type,Scope,BOM-Ref")
      lines.size.should eq(4) # header + root application + 2 dependencies
      # The root application component (from metadata.component) is included so
      # the CSV is consistent with the JSON/XML output.
      output.should contain("test-app,0.1.0,,application")
    end

    it "neutralises spreadsheet formula injection in component names" do
      # A shard.yml name beginning with '=' would be evaluated as a formula when
      # the export is opened in Excel/Sheets, so it must be quoted out.
      output = `#{BINARY} -s #{FIXTURES}/csv_injection_shard.yml -i #{FIXTURES}/empty_lock.lock --output-format csv 2>&1`
      $?.success?.should be_true
      output.should contain("'=cmd|")
      output.should_not match(/^=cmd/m)
    end
  end

  describe "file output" do
    it "writes BOM to file with -o flag" do
      tmpfile = File.tempname("cyclonedx", ".json")
      begin
        stderr = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock -o #{tmpfile} 2>&1`
        $?.success?.should be_true

        content = File.read(tmpfile)
        bom = JSON.parse(content)
        bom["bomFormat"].should eq("CycloneDX")
      ensure
        File.delete?(tmpfile)
      end
    end
  end

  describe "GitLab PURL support" do
    it "generates PURL for gitlab shorthand dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/gitlab_lock.lock 2>/dev/null`
      $?.success?.should be_true
      components = JSON.parse(output)["components"].as_a

      my_lib = components.find! { |c| c["name"] == "my_lib" }
      my_lib["purl"].should eq("pkg:gitlab/myorg/my_lib@v2.0.0")
    end

    it "generates PURL for gitlab git URL dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/gitlab_lock.lock 2>/dev/null`
      components = JSON.parse(output)["components"].as_a

      other_lib = components.find! { |c| c["name"] == "other_lib" }
      other_lib["purl"].should eq("pkg:gitlab/otherorg/other_lib@v1.0.0")
    end
  end

  describe "minimal shard.yml" do
    it "handles shard.yml without optional fields" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true

      bom = JSON.parse(output)
      component = bom["metadata"]["component"]
      component["name"].should eq("minimal")
      component["version"].should eq("0.0.1")
      bom["components"].as_a.should be_empty
    end
  end

  describe "URL validation" do
    it "excludes invalid URLs from external references" do
      output = `#{BINARY} -s #{FIXTURES}/bad_urls_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true

      component = JSON.parse(output)["metadata"]["component"]
      component["externalReferences"]?.should be_nil
    end

    it "normalizes an scp-style git remote into a valid ssh:// URI" do
      # `git@host:owner/repo.git` is not a valid URI and would fail CycloneDX
      # url validation; it must be rewritten to its ssh:// equivalent.
      output = `#{BINARY} -s #{FIXTURES}/scp_url_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true

      refs = JSON.parse(output)["metadata"]["component"]["externalReferences"].as_a
      vcs = refs.find!(&.["type"].as_s.== "vcs")
      vcs["url"].as_s.should eq("ssh://git@github.com/owner/repo.git")
      output.should_not contain("git@github.com:owner/repo.git")
    end
  end

  describe "SPDX license expression" do
    it "outputs license expression inside licenses array for compound licenses" do
      output = `#{BINARY} -s #{FIXTURES}/spdx_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true

      component = JSON.parse(output)["metadata"]["component"]
      licenses = component["licenses"].as_a
      licenses.size.should eq(1)
      licenses[0]["expression"].should eq("MIT OR Apache-2.0")
    end

    it "outputs license expression in XML" do
      output = `#{BINARY} -s #{FIXTURES}/spdx_shard.yml -i #{FIXTURES}/empty_lock.lock --output-format xml 2>&1`
      $?.success?.should be_true
      output.should contain("<expression>MIT OR Apache-2.0</expression>")
    end

    it "uses the SPDX id (not name) for licenses present in the SPDX list" do
      # SPDX recognizes "MIT", so we emit the canonical id field rather
      # than the free-form name field.
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      component = JSON.parse(output)["metadata"]["component"]
      license = component["licenses"].as_a[0]["license"]
      license["id"].should eq("MIT")
      license["name"]?.should be_nil
    end

    it "falls back to license name for identifiers not in the SPDX list" do
      output = `#{BINARY} -s #{FIXTURES}/custom_license_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true
      component = JSON.parse(output)["metadata"]["component"]
      license = component["licenses"].as_a[0]["license"]
      license["name"].should eq("Proprietary")
      license["id"]?.should be_nil
    end

    it "does NOT treat a free-form string containing OR as an SPDX expression" do
      # "Free for personal OR commercial use" contains "OR" but is not a valid
      # SPDX expression, so it must fall back to the free-form license name.
      output = `#{BINARY} -s #{FIXTURES}/freeform_or_license_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true
      component = JSON.parse(output)["metadata"]["component"]
      licenses = component["licenses"].as_a
      licenses.size.should eq(1)
      licenses[0]["expression"]?.should be_nil
      licenses[0]["license"]["name"].should eq("Free for personal OR commercial use")
    end

    it "does NOT treat a grammatically-valid string of unknown license ids as an expression" do
      # "Foo AND Bar" parses as an SPDX expression grammatically, but neither
      # operand is a real SPDX license, so it must fall back to a free-form name.
      output = `#{BINARY} -s #{FIXTURES}/bogus_expr_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true
      licenses = JSON.parse(output)["metadata"]["component"]["licenses"].as_a
      licenses[0]["expression"]?.should be_nil
      licenses[0]["license"]["name"].should eq("Foo AND Bar")
    end

    it "does NOT treat an expression with an unknown WITH exception as an expression" do
      output = `#{BINARY} -s #{FIXTURES}/bogus_exception_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true
      licenses = JSON.parse(output)["metadata"]["component"]["licenses"].as_a
      licenses[0]["expression"]?.should be_nil
      licenses[0]["license"]["name"].should eq("MIT WITH Bogus-Exception")
    end

    # CycloneDX: `license.id` only for a bare id from the SPDX list (the enum),
    # `expression` for any other valid SPDX expression, `name` for free text.
    {
      "Apache-2.0"                                    => {"id", "Apache-2.0"},
      "apache-2.0"                                    => {"id", "Apache-2.0"},
      "Apache-2.0+"                                   => {"expression", "Apache-2.0+"},
      "LicenseRef-Foo"                                => {"expression", "LicenseRef-Foo"},
      "DocumentRef-spdx-doc:LicenseRef-Foo"           => {"expression", "DocumentRef-spdx-doc:LicenseRef-Foo"},
      "GPL-2.0-or-later WITH Classpath-exception-2.0" => {"expression", "GPL-2.0-or-later WITH Classpath-exception-2.0"},
      "Foo+"                                          => {"name", "Foo+"},
    }.each do |license, (field, value)|
      it "emits #{license.inspect} as license #{field}" do
        shard = File.tempname("cdx-license", ".yml")
        begin
          File.write(shard, {"name" => "lic", "version" => "0.1.0", "license" => license}.to_yaml)
          output = `#{BINARY} -s #{shard} -i #{FIXTURES}/empty_lock.lock 2>&1`
          $?.success?.should be_true
          choice = JSON.parse(output)["metadata"]["component"]["licenses"][0]
          actual = field == "expression" ? choice["expression"] : choice["license"][field]
          actual.should eq(value)

          if SchemaValidation::JSON_VALIDATOR
            ok, err = SchemaValidation.json_schema_validate(output, "1.6")
            fail(err) unless ok
          end
          if SchemaValidation::XMLLINT
            ok, err = SchemaValidation.xsd_validate(`#{BINARY} -s #{shard} -i #{FIXTURES}/empty_lock.lock --output-format xml 2>&1`, "1.6")
            fail(err) unless ok
          end
        ensure
          File.delete?(shard)
        end
      end
    end

    it "still treats a valid expression with a deprecated id as an SPDX expression" do
      # Deprecated ids (GPL-2.0+) are still valid SPDX expressions, so the
      # compound must be emitted as an expression, not a free-form name.
      output = `#{BINARY} -s #{FIXTURES}/deprecated_expr_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_true
      licenses = JSON.parse(output)["metadata"]["component"]["licenses"].as_a
      licenses[0]["expression"].should eq("GPL-2.0+ OR MIT")
    end
  end

  describe "PURL canonicalization and encoding" do
    it "lowercases the namespace/name for github (case-insensitive type)" do
      canon_purls["gh_upper"].should eq("pkg:github/sysexitcode/foo@v1.0.0")
    end

    it "still produces a PURL when a git URL has a trailing slash" do
      canon_purls["gh_trailing"].should eq("pkg:github/owner/repo@v1.2.3")
    end

    it "percent-encodes reserved characters in the version" do
      # '+' build metadata must be encoded as %2B per the PURL spec.
      canon_purls["gh_buildmeta"].should eq("pkg:github/hahwul/spdx.cr@0.1.0%2Bbuild.5")
    end

    it "emits a pkg:bitbucket PURL for bitbucket git URLs (lowercased)" do
      canon_purls["bb_url"].should eq("pkg:bitbucket/team/proj@v3.0.0")
    end

    it "captures the full path for gitlab subgroup git URLs" do
      canon_purls["gl_subgroup"].should eq("pkg:gitlab/group/subgroup/repo@v1.1.1")
    end

    it "preserves case for gitlab (case-sensitive type)" do
      canon_purls["gl_key"].should eq("pkg:gitlab/MyOrg/MyLib@v2.0.0")
    end

    it "does not leak an explicit port from an ssh github URL into the PURL" do
      canon_purls["gh_ssh_port"].should eq("pkg:github/owner/repo@v4.0.0")
    end

    it "does not leak an explicit port from a gitlab URL into the PURL namespace" do
      canon_purls["gl_port"].should eq("pkg:gitlab/group/repo@v5.0.0")
    end

    it "strips a ?query from a git URL instead of leaking it into the PURL name" do
      canon_purls["gh_query"].should eq("pkg:github/owner/repo@v6.0.0")
    end

    it "strips a #fragment from a git URL instead of leaking it into the PURL name" do
      canon_purls["gl_fragment"].should eq("pkg:gitlab/group/subgroup/repo@v7.0.0")
    end

    it "produces a canonical PURL when a git URL has a trailing slash before a query" do
      canon_purls["gh_trailing_query"].should eq("pkg:github/owner/repo@v8.0.0")
    end
  end

  describe "PURL forge-host matching" do
    # A PURL is an identity claim: `pkg:github/owner/repo` tells a scanner to
    # resolve the component against that GitHub project. Matching `github.com`
    # as a substring of the whole URL (rather than as the parsed host) attributes
    # components to upstream projects they do not come from.
    it "does not treat a look-alike host as the forge host" do
      foreign_purls["lookalike_host"]?.should be_nil
    end

    it "does not treat a forge name appearing in the path as the forge host" do
      # A corporate mirror serving upstream repos under `/github.com/owner/repo`
      # is a real layout; the component is not hosted on GitHub.
      foreign_purls["mirror_path"]?.should be_nil
    end

    it "matches the host, not the userinfo" do
      foreign_purls["userinfo_host"]?.should be_nil
    end

    it "matches the forge host case-insensitively" do
      # Hosts are case-insensitive (RFC 3986), so an uppercase host is still
      # GitHub and must not silently lose its PURL.
      foreign_purls["uppercase_host"].should eq("pkg:github/owner/repo@v1.0.0")
    end

    it "matches the forge host case-insensitively for scp-style remotes" do
      foreign_purls["scp_uppercase"].should eq("pkg:github/owner/repo@v1.0.0")
    end
  end

  describe "repository shorthand normalization" do
    # `github:`/`gitlab:` in shard.lock is a plain `namespace/name`. Anything
    # else is malformed, and a malformed PURL is worse than an absent one.
    it "skips a PURL for a shorthand carrying a full URL" do
      shorthand_purls["full_url"]?.should be_nil
    end

    it "skips a PURL for a shorthand with too many path segments" do
      shorthand_purls["too_deep"]?.should be_nil
    end

    it "skips a PURL for a shorthand missing a namespace" do
      shorthand_purls["bare_name"]?.should be_nil
    end

    it "warns when it skips a malformed shorthand" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/shorthand_lock.lock 2>&1`
      output.should contain("malformed repository shorthand")
    end

    it "tolerates a .git suffix on a shorthand" do
      shorthand_purls["dot_git_suffix"].should eq("pkg:github/owner/repo@v1.0.0")
    end

    it "tolerates a trailing slash on a shorthand" do
      shorthand_purls["trailing_slash"].should eq("pkg:github/owner/repo@v1.0.0")
    end
  end

  describe "unversioned lock entries" do
    it "omits the version component from the PURL instead of asserting 'unknown'" do
      # `unknown` is a not-known placeholder, not a version. The package-url
      # encoding for an unknown version is to omit `@version` entirely.
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/unversioned_lock.lock 2>/dev/null`
      $?.success?.should be_true
      components = JSON.parse(output)["components"].as_a

      github_dep = components.find! { |c| c["name"] == "no_version_github" }
      github_dep["purl"].should eq("pkg:github/owner/repo")

      # Only the PURL is affected. `bom-ref` is an opaque identifier and the
      # `version` field still carries the placeholder, so neither is asserted
      # against here.
      components.each { |c| c["purl"]?.try(&.as_s.should_not(contain("@unknown"))) }
    end
  end

  describe "dependency graph" do
    it "builds the real graph from the installed shards" do
      json, err = run_graph
      err.should be_empty
      bom = JSON.parse(json)

      # The root depends on its direct dependencies only (runtime and dev), not
      # on everything in shard.lock; the diamond on charlie is shared.
      edges(bom).should eq({
        "graph-root@1.0.0" => ["alpha@1.0.0", "bravo@1.0.0", "delta@1.0.0"],
        "alpha@1.0.0"      => ["charlie@1.0.0"],
        "bravo@1.0.0"      => ["charlie@1.0.0"],
        "charlie@1.0.0"    => [] of String,
        # delta's development_dependencies are never installed, so not edges.
        "delta@1.0.0" => ["charlie@1.0.0", "echo@1.0.0"],
        "echo@1.0.0"  => [] of String,
      })
      aggregates(bom).should eq({"complete" => edges(bom).keys})
    end

    it "marks shards reachable only through dev dependencies optional" do
      bom = JSON.parse(run_graph[0])
      # charlie is needed by delta (dev) but also by alpha/bravo (runtime).
      scopes(bom).should eq({
        "alpha" => "required", "bravo" => "required", "charlie" => "required",
        "delta" => "optional", "echo" => "optional",
      })
    end

    it "reports unreadable and out-of-sync shards honestly" do
      json, err = run_graph("#{GRAPH}/lib_partial")
      err.should contain("lib_partial/bravo/shard.yml` (")
      err.should contain("the dependencies of `bravo` are unknown")
      err.should contain("`alpha@1.0.0` depends on `ghost`, which is not in shard.lock")
      err.should contain("installed `echo` is 0.9.0 but shard.lock pins 1.0.0")
      err.should_not contain("graph-root`")
      bom = JSON.parse(json)

      # bravo (not installed) and echo (stale install) are absent from the graph
      # rather than listed as leaves: an empty dependsOn would assert they have
      # no dependencies.
      edges(bom).has_key?("bravo@1.0.0").should be_false
      edges(bom).has_key?("echo@1.0.0").should be_false
      edges(bom)["alpha@1.0.0"].should eq(["charlie@1.0.0"])
      # An edge back to the root project resolves to the root component.
      edges(bom)["charlie@1.0.0"].should eq(["graph-root@1.0.0"])
      aggregates(bom).should eq({
        "complete"   => ["graph-root@1.0.0", "charlie@1.0.0", "delta@1.0.0"],
        "incomplete" => ["alpha@1.0.0"],
        "unknown"    => ["bravo@1.0.0", "echo@1.0.0"],
      })
      # bravo's edges are unknown, so echo cannot be shown to be dev-only; the
      # direct dev dependency stays optional.
      scopes(bom)["echo"].should eq("required")
      scopes(bom)["delta"].should eq("optional")
    end

    it "falls back to an unknown graph when nothing is installed" do
      json, err = run_graph("#{GRAPH}/not-installed")
      err.lines.size.should eq(1)
      err.should contain("run `shards install`")
      bom = JSON.parse(json)

      edges(bom).keys.should eq(["graph-root@1.0.0"])
      aggregates(bom)["unknown"].size.should eq(5)
      scopes(bom)["delta"].should eq("optional")
    end

    it "emits schema-valid graphs" do
      [nil, "#{GRAPH}/lib_partial"].each do |install|
        SchemaValidation::VERSIONS.each do |version|
          if SchemaValidation::JSON_VALIDATOR
            ok, err = SchemaValidation.json_schema_validate(run_graph(install, ["--spec-version", version])[0], version)
            fail("bom-#{version}.schema.json validation failed:\n#{err}") unless ok
          end
          if SchemaValidation::XMLLINT
            xml = run_graph(install, ["--spec-version", version, "--output-format", "xml"])[0]
            ok, err = SchemaValidation.xsd_validate(xml, version)
            fail("bom-#{version}.xsd validation failed:\n#{err}") unless ok
          end
        end
      end
      if SchemaValidation::XMLLINT.nil? && SchemaValidation::JSON_VALIDATOR.nil?
        pending!("neither xmllint nor check-jsonschema is installed")
      end
    end
  end

  describe "warnings" do
    it "escapes control characters so a name cannot forge a CI workflow command" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/control_char_lock.lock 2>&1 >/dev/null`
      output.should contain("malformed repository shorthand 'o/r/x\\n::error::pwned'")
      output.lines.none?(&.starts_with?("::")).should be_true
    end
  end

  describe "blank versions" do
    it "treats an empty version as absent instead of failing" do
      output = `#{BINARY} -s #{FIXTURES}/blank_version_shard.yml -i #{FIXTURES}/blank_version_lock.lock 2>/dev/null`
      $?.success?.should be_true
      bom = JSON.parse(output)
      bom["metadata"]["component"]["version"]?.should be_nil
      blank = bom["components"].as_a.first
      blank["version"]?.should be_nil
      blank["purl"].should eq("pkg:github/owner/blank")
      if SchemaValidation::JSON_VALIDATOR
        ok, err = SchemaValidation.json_schema_validate(output, "1.6")
        fail(err) unless ok
      end
    end
  end

  describe "dependency scope" do
    it "keeps a shard required when it is declared as both a runtime and a dev dependency" do
      # Runtime membership wins: the shard is still needed at runtime, so
      # reporting it as `optional` understates its scope.
      output = `#{BINARY} -s #{FIXTURES}/dual_scope_shard.yml -i #{FIXTURES}/dual_scope_lock.lock 2>/dev/null`
      $?.success?.should be_true
      components = JSON.parse(output)["components"].as_a

      components.find! { |c| c["name"] == "shared_dep" }["scope"].should eq("required")
      components.find! { |c| c["name"] == "dev_only" }["scope"].should eq("optional")
    end
  end

  describe "generated BOM validation" do
    it "fails instead of emitting a component with an empty name" do
      # Blank names are already rejected for lock entries; the root component
      # from shard.yml must not be able to bypass the same rule.
      output = `#{BINARY} -s #{FIXTURES}/blank_name_shard.yml -i #{FIXTURES}/empty_lock.lock 2>&1`
      $?.success?.should be_false
      output.should contain("not valid CycloneDX")
      output.should contain("$.metadata.component.name")
      output.should contain("must not be empty")
    end
  end

  describe "robustness" do
    it "rejects stray positional arguments" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock stray 2>&1`
      $?.success?.should be_false
      output.should contain("Unexpected argument")
    end

    it "rejects a bare dash argument" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock - 2>&1`
      $?.success?.should be_false
      output.should contain("Unexpected argument")
    end

    it "skips lock entries with an empty shard name" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/empty_name_lock.lock 2>&1`
      $?.success?.should be_true
      output.should contain("empty shard name")
      bom = JSON.parse(output.lines.reject(&.starts_with?("Warning")).join("\n"))
      names = bom["components"].as_a.map(&.["name"].as_s)
      names.should eq(["good"])
    end

    it "does not emit a duplicate bom-ref or self-edge on a name@version collision" do
      output = `#{BINARY} -s #{FIXTURES}/self_dep_shard.yml -i #{FIXTURES}/self_dep_lock.lock 2>&1`
      $?.success?.should be_true
      output.should contain("duplicates the root component ref")
      bom = JSON.parse(output.lines.reject(&.starts_with?("Warning")).join("\n"))

      # The colliding lock entry is dropped, so no component re-uses the root
      # component's bom-ref (CycloneDX requires bom-refs to be unique).
      component_refs = bom["components"].as_a.compact_map(&.["bom-ref"]?.try(&.as_s))
      component_refs.should_not contain("dup@9.9.9")

      deps = bom["dependencies"].as_a
      root = deps.find!(&.["ref"].as_s.== "dup@9.9.9")
      root["dependsOn"].as_a.should be_empty
      # the same ref must not appear as more than one top-level dependency entry
      deps.count(&.["ref"].as_s.== "dup@9.9.9").should eq(1)

      # Every bom-ref in the document (root + components) is unique.
      all_refs = component_refs.dup
      bom["metadata"]["component"]["bom-ref"]?.try { |r| all_refs << r.as_s }
      all_refs.size.should eq(all_refs.uniq.size)
    end
  end

  describe "shard source coverage" do
    it "emits a PURL for every forge shorthand, canonicalised" do
      components = all_resolver_components
      # github and bitbucket namespaces are case-insensitive and must be folded.
      components["gh"]["purl"].should eq("pkg:github/kemalcr/kemal@v1.4.0")
      components["bb"]["purl"].should eq("pkg:bitbucket/team/bbrepo@v1.2.3")
    end

    it "uses the locked commit rather than shards' composite version string" do
      purl = all_resolver_components["gh_commit"]["purl"].as_s
      purl.should eq("pkg:github/hahwul/spdx.cr@21ac950936830412628cbf631bf48ece6dce9a48")
      purl.should_not contain("git.commit")
    end

    it "records a vcs external reference for sources that have no PURL type" do
      components = all_resolver_components

      {
        "cb"        => "https://codeberg.org/team/cbrepo",
        "hgdep"     => "https://hg.example.com/repo",
        "fossildep" => "https://fossil.example.com/repo",
      }.each do |name, url|
        component = components[name]
        component["purl"]?.should be_nil
        refs = component["externalReferences"].as_a
        refs.map(&.["url"].as_s).should contain(url)
        refs.map(&.["type"].as_s).should contain("vcs")
      end
    end

    it "uses the reference a version 1.0 lock file names directly" do
      # A `version: 1.0` lock (still readable by shards) records `commit:`/`tag:`
      # instead of folding the reference into `version`. Ignoring those keys left
      # the PURL with no version at all, even though the file names the exact
      # tree that was installed.
      purls = purls_for("#{FIXTURES}/legacy_v1_lock.lock")
      purls["pinned"].should eq("pkg:github/crystal-ameba/ameba@0f4b2d5a1c9e7f3b8a6d4c2e0f1a3b5c7d9e1f20")
      purls["tagged"].should eq("pkg:github/kemalcr/kemal@v1.4.0")
      # A branch is neither a tag nor a commit: it names a moving target, not the
      # installed tree, so it must not be asserted as the PURL version.
      purls["tracked"].should eq("pkg:github/owner/tracked")
    end

    it "names the vX.Y.Z tag shards installs a release from" do
      # shards' git resolver checks a release out from the tag `v#{version}`;
      # `pkg:github/kemalcr/kemal@1.4.0` names a tag that does not exist.
      all_resolver_components["gh"]["purl"].should eq("pkg:github/kemalcr/kemal@v1.4.0")
    end

    it "keeps credentials out of vcs references" do
      # Private dependencies are declared with a token in the URL, shard.lock
      # keeps it verbatim, and an SBOM gets published.
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/credentials_lock.lock 2>/dev/null`
      $?.success?.should be_true
      output.should_not contain("SECRETTOKEN")

      urls = JSON.parse(output)["components"].as_a.to_h do |c|
        {c["name"].as_s, c["externalReferences"]?.try(&.as_a.map(&.["url"].as_s)) || [] of String}
      end
      urls["token_user"].should eq(["https://github.com/owner/private.git"])
      urls["user_pass"].should eq(["https://gitlab.example.com/group/repo.git"])
      # Over ssh the user is the login, not a secret; ssh:// remotes are recorded.
      urls["ssh_user"].should eq(["ssh://git@git.example.com:2222/team/repo.git"])
      urls["ssh_pass"].should eq(["ssh://deploy@hg.example.com/repo"])
      # A remote's query is not published: `?private_token=` authenticates.
      urls["token_query"].should eq(["https://gitlab.example.com/group/query.git"])
      # An unencoded `@` in the password would put part of it in the host, and a
      # port too big to parse used to crash the run; neither is published.
      urls["at_in_password"].should be_empty
      urls["huge_port"].should be_empty
      # Nor is one whose token holds a `/` or `#`, which ends the authority early.
      urls["slash_in_token"].should be_empty
      urls["hash_in_token"].should be_empty
    end

    it "does not read a shard.yml outside the install dir for a path-like lock name" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/traversal_lock.lock 2>&1`
      $?.success?.should be_true
      output.should contain("is not a valid shard name")
      # spec/fixtures/graph/lib/alpha/shard.yml depends on charlie.
      output.should_not contain("charlie")
    end

    it "omits the version entirely for a dependency that has none" do
      component = all_resolver_components["localdep"]
      component["version"]?.should be_nil
      component["bom-ref"].should eq("localdep")
      # A `path:` dependency has no remote to point at.
      component["externalReferences"]?.should be_nil
    end
  end

  describe "BOM-level assertions" do
    it "types the root component from the presence of build targets" do
      with_targets = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`
      JSON.parse(with_targets)["metadata"]["component"]["type"].should eq("application")

      without_targets = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/empty_lock.lock 2>/dev/null`
      JSON.parse(without_targets)["metadata"]["component"]["type"].should eq("library")
    end

    it "emits all shard.yml authors as structured contacts" do
      bom = JSON.parse(`#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`)
      authors = bom["metadata"]["component"]["authors"].as_a
      authors.map(&.["name"].as_s).should eq(["Test Author", "Second Author"])
      authors.map(&.["email"].as_s).should eq(["test@example.com", "second@example.com"])
    end

    it "keeps an author whose bracketed part is not an address as a plain name" do
      # The JSON schemas type `email` as `idn-email`, so `n/a` must not become one.
      output = `#{BINARY} -s #{FIXTURES}/non_email_author_shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`
      authors = JSON.parse(output)["metadata"]["component"]["authors"].as_a
      authors[0]["email"].should eq("jane@example.com")
      authors[1]["name"].should eq("Team <n/a>")
      authors[1]["email"]?.should be_nil
      if SchemaValidation::JSON_VALIDATOR
        ok, err = SchemaValidation.json_schema_validate(output, "1.6")
        fail(err) unless ok
      end
    end

    it "omits the 1.6-only authors array for older spec versions" do
      %w[1.4 1.5].each do |version|
        output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --spec-version #{version} 2>&1`
        # No gate warning either: the CLI never populates it below 1.6.
        output.should_not contain("Warning")
        component = JSON.parse(output)["metadata"]["component"]
        component["authors"]?.should be_nil
        component["author"].should eq("Test Author <test@example.com>")
      end
    end

    it "emits a $schema matching the requested spec version" do
      CycloneDX::BOM::SUPPORTED_VERSIONS.each do |version|
        output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --spec-version #{version} 2>/dev/null`
        JSON.parse(output)["$schema"]
          .should eq("http://cyclonedx.org/schema/bom-#{version}.schema.json")
      end
    end
  end

  describe "--reproducible" do
    it "produces byte-identical output across runs" do
      first = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --reproducible 2>/dev/null`
      second = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --reproducible 2>/dev/null`
      first.should eq(second)

      bom = JSON.parse(first)
      bom["serialNumber"].should eq("urn:uuid:00000000-0000-0000-0000-000000000000")
      bom["metadata"]["timestamp"].should eq("1970-01-01T00:00:00Z")
    end

    it "varies the serial number when not requested" do
      first = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`
      second = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`
      JSON.parse(first)["serialNumber"].should_not eq(JSON.parse(second)["serialNumber"])
    end
  end

  # The library specs validate hand-built BOMs; this checks what the binary
  # actually writes, for every spec version and both serializations.
  describe "generated documents validate against the official schemas" do
    SchemaValidation::VERSIONS.each do |version|
      it "emits schema-valid JSON and XML (spec #{version})" do
        args = "-s #{FIXTURES}/shard.yml -i #{FIXTURES}/all_resolvers_lock.lock " \
               "--spec-version #{version} --reproducible"

        if SchemaValidation::JSON_VALIDATOR
          json = `#{BINARY} #{args} 2>/dev/null`
          ok, err = SchemaValidation.json_schema_validate(json, version)
          fail("bom-#{version}.schema.json validation failed:\n#{err}") unless ok
        end

        if SchemaValidation::XMLLINT
          xml = `#{BINARY} #{args} --output-format xml 2>/dev/null`
          ok, err = SchemaValidation.xsd_validate(xml, version)
          fail("bom-#{version}.xsd validation failed:\n#{err}") unless ok
        end

        if SchemaValidation::XMLLINT.nil? && SchemaValidation::JSON_VALIDATOR.nil?
          pending!("neither xmllint nor check-jsonschema is installed")
        end
      end
    end
  end
end
