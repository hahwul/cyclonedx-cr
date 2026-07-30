require "spec"
require "json"
require "../src/cyclonedx/bom"
require "./support/schema_validation"

BINARY   = "bin/cyclonedx-cr"
FIXTURES = "spec/fixtures"

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
      kemal["purl"].should eq("pkg:github/kemalcr/kemal@1.4.0")
    end

    it "generates PURL for git URL dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      ameba = components.find! { |c| c["name"] == "ameba" }
      ameba["purl"].should eq("pkg:github/crystal-ameba/ameba@1.6.4")
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
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/gitlab_lock.lock 2>&1`
      $?.success?.should be_true
      components = JSON.parse(output)["components"].as_a

      my_lib = components.find! { |c| c["name"] == "my_lib" }
      my_lib["purl"].should eq("pkg:gitlab/myorg/my_lib@2.0.0")
    end

    it "generates PURL for gitlab git URL dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/gitlab_lock.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      other_lib = components.find! { |c| c["name"] == "other_lib" }
      other_lib["purl"].should eq("pkg:gitlab/otherorg/other_lib@1.0.0")
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
      canon_purls["gh_upper"].should eq("pkg:github/sysexitcode/foo@1.0.0")
    end

    it "still produces a PURL when a git URL has a trailing slash" do
      canon_purls["gh_trailing"].should eq("pkg:github/owner/repo@1.2.3")
    end

    it "percent-encodes reserved characters in the version" do
      # '+' build metadata must be encoded as %2B per the PURL spec.
      canon_purls["gh_buildmeta"].should eq("pkg:github/hahwul/spdx.cr@0.1.0%2Bgit.commit.abc")
    end

    it "emits a pkg:bitbucket PURL for bitbucket git URLs (lowercased)" do
      canon_purls["bb_url"].should eq("pkg:bitbucket/team/proj@3.0.0")
    end

    it "captures the full path for gitlab subgroup git URLs" do
      canon_purls["gl_subgroup"].should eq("pkg:gitlab/group/subgroup/repo@1.1.1")
    end

    it "preserves case for gitlab (case-sensitive type)" do
      canon_purls["gl_key"].should eq("pkg:gitlab/MyOrg/MyLib@2.0.0")
    end

    it "does not leak an explicit port from an ssh github URL into the PURL" do
      canon_purls["gh_ssh_port"].should eq("pkg:github/owner/repo@4.0.0")
    end

    it "does not leak an explicit port from a gitlab URL into the PURL namespace" do
      canon_purls["gl_port"].should eq("pkg:gitlab/group/repo@5.0.0")
    end

    it "strips a ?query from a git URL instead of leaking it into the PURL name" do
      canon_purls["gh_query"].should eq("pkg:github/owner/repo@6.0.0")
    end

    it "strips a #fragment from a git URL instead of leaking it into the PURL name" do
      canon_purls["gl_fragment"].should eq("pkg:gitlab/group/subgroup/repo@7.0.0")
    end

    it "produces a canonical PURL when a git URL has a trailing slash before a query" do
      canon_purls["gh_trailing_query"].should eq("pkg:github/owner/repo@8.0.0")
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
      foreign_purls["uppercase_host"].should eq("pkg:github/owner/repo@1.0.0")
    end

    it "matches the forge host case-insensitively for scp-style remotes" do
      foreign_purls["scp_uppercase"].should eq("pkg:github/owner/repo@1.0.0")
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
      shorthand_purls["dot_git_suffix"].should eq("pkg:github/owner/repo@1.0.0")
    end

    it "tolerates a trailing slash on a shorthand" do
      shorthand_purls["trailing_slash"].should eq("pkg:github/owner/repo@1.0.0")
    end
  end

  describe "unversioned lock entries" do
    it "omits the version component from the PURL instead of asserting 'unknown'" do
      # `unknown` is a not-known placeholder, not a version. The package-url
      # encoding for an unknown version is to omit `@version` entirely.
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/unversioned_lock.lock 2>&1`
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

  describe "dependency scope" do
    it "keeps a shard required when it is declared as both a runtime and a dev dependency" do
      # Runtime membership wins: the shard is still needed at runtime, so
      # reporting it as `optional` understates its scope.
      output = `#{BINARY} -s #{FIXTURES}/dual_scope_shard.yml -i #{FIXTURES}/dual_scope_lock.lock 2>&1`
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
      components["gh"]["purl"].should eq("pkg:github/kemalcr/kemal@1.4.0")
      components["bb"]["purl"].should eq("pkg:bitbucket/team/bbrepo@1.2.3")
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

    it "declares the dependency graph incomplete" do
      bom = JSON.parse(`#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`)
      composition = bom["compositions"].as_a.first
      composition["aggregate"].should eq("incomplete")
      # Every ref in the graph is covered by the assertion.
      graph_refs = bom["dependencies"].as_a.map(&.["ref"].as_s)
      composition["dependencies"].as_a.map(&.as_s).sort!.should eq(graph_refs.sort)
    end

    it "emits all shard.yml authors as structured contacts" do
      bom = JSON.parse(`#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>/dev/null`)
      authors = bom["metadata"]["component"]["authors"].as_a
      authors.map(&.["name"].as_s).should eq(["Test Author", "Second Author"])
      authors.map(&.["email"].as_s).should eq(["test@example.com", "second@example.com"])
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
