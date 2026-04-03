require "spec"
require "json"

BINARY   = "bin/cyclonedx-cr"
FIXTURES = "spec/fixtures"

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

    it "includes licenses from shard.yml" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      component = JSON.parse(output)["metadata"]["component"]
      licenses = component["licenses"].as_a
      licenses.size.should eq(1)
      licenses[0]["name"].should eq("MIT")
    end

    it "includes dependencies as components" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a
      components.size.should eq(2)

      names = components.map { |c| c["name"].as_s }
      names.should contain("kemal")
      names.should contain("ameba")
    end

    it "sets correct scope for dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      kemal = components.find { |c| c["name"] == "kemal" }.not_nil!
      kemal["scope"].should eq("required")

      ameba = components.find { |c| c["name"] == "ameba" }.not_nil!
      ameba["scope"].should eq("optional")
    end

    it "generates PURL for github dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      kemal = components.find { |c| c["name"] == "kemal" }.not_nil!
      kemal["purl"].should eq("pkg:github/kemalcr/kemal@1.4.0")
    end

    it "generates PURL for git URL dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      ameba = components.find { |c| c["name"] == "ameba" }.not_nil!
      ameba["purl"].should eq("pkg:github/crystal-ameba/ameba@1.6.4")
    end

    it "generates dependency graph" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      deps = JSON.parse(output)["dependencies"].as_a

      main_dep = deps.find { |d| d["ref"].as_s.starts_with?("test-app@") }.not_nil!
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
    it "generates CSV with header and components" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock --output-format csv 2>&1`
      $?.success?.should be_true
      lines = output.strip.split("\n")
      lines[0].should eq("Name,Version,PURL,Type")
      lines.size.should eq(3) # header + 2 dependencies
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

      my_lib = components.find { |c| c["name"] == "my_lib" }.not_nil!
      my_lib["purl"].should eq("pkg:gitlab/myorg/my_lib@2.0.0")
    end

    it "generates PURL for gitlab git URL dependencies" do
      output = `#{BINARY} -s #{FIXTURES}/minimal_shard.yml -i #{FIXTURES}/gitlab_lock.lock 2>&1`
      components = JSON.parse(output)["components"].as_a

      other_lib = components.find { |c| c["name"] == "other_lib" }.not_nil!
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

    it "uses license name for simple licenses" do
      output = `#{BINARY} -s #{FIXTURES}/shard.yml -i #{FIXTURES}/shard.lock 2>&1`
      component = JSON.parse(output)["metadata"]["component"]
      component["licenses"].as_a[0]["name"].should eq("MIT")
    end
  end
end
