require "spec"
require "json"

BINARY   = "bin/cyclonedx-cr"
FIXTURES = "spec/fixtures"

# Runs the binary against the PURL-canonicalization fixture and returns a
# name => purl map for the emitted components.
private def canon_purls : Hash(String, String)
  output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/purl_canon_lock.lock 2>&1`
  result = {} of String => String
  JSON.parse(output)["components"].as_a.each do |c|
    if purl = c["purl"]?
      result[c["name"].as_s] = purl.as_s
    end
  end
  result
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
      lines[0].should eq("Name,Version,PURL,Type")
      lines.size.should eq(4) # header + root application + 2 dependencies
      # The root application component (from metadata.component) is included so
      # the CSV is consistent with the JSON/XML output.
      output.should contain("test-app,0.1.0,,application")
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
  end

  describe "robustness" do
    it "rejects stray positional arguments" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock stray 2>&1`
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

    it "does not emit a self-referential dependency edge on a name@version collision" do
      output = `#{BINARY} -s #{FIXTURES}/self_dep_shard.yml -i #{FIXTURES}/self_dep_lock.lock 2>&1`
      $?.success?.should be_true
      deps = JSON.parse(output)["dependencies"].as_a
      root = deps.find!(&.["ref"].as_s.== "dup@9.9.9")
      root["dependsOn"].as_a.should be_empty
      # the same ref must not appear as more than one top-level dependency entry
      deps.count(&.["ref"].as_s.== "dup@9.9.9").should eq(1)
    end
  end
end
