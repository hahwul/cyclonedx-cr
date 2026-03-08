require "spec"
require "../src/shard/shard_file"

describe ShardFile do
  describe ".from_yaml" do
    it "parses a shard.yml with all fields" do
      yaml = <<-YAML
        name: my-shard
        version: 0.1.0
        description: A sample shard
        authors:
          - Alice <alice@example.com>
          - Bob <bob@example.com>
        license: MIT
        homepage: https://example.com
        repository: https://github.com/example/my-shard
        YAML

      shard = ShardFile.from_yaml(yaml)

      shard.name.should eq "my-shard"
      shard.version.should eq "0.1.0"
      shard.description.should eq "A sample shard"
      shard.authors.should eq ["Alice <alice@example.com>", "Bob <bob@example.com>"]
      shard.license.should eq "MIT"
      shard.homepage.should eq "https://example.com"
      shard.repository.should eq "https://github.com/example/my-shard"
    end

    it "parses a shard.yml with minimal fields" do
      yaml = <<-YAML
        name: minimal-shard
        version: 1.0.0
        YAML

      shard = ShardFile.from_yaml(yaml)

      shard.name.should eq "minimal-shard"
      shard.version.should eq "1.0.0"
      shard.description.should be_nil
      shard.authors.should be_nil
      shard.license.should be_nil
      shard.homepage.should be_nil
      shard.repository.should be_nil
    end

    it "raises an error when required fields are missing" do
      yaml = <<-YAML
        description: Missing name and version
        YAML

      expect_raises(YAML::ParseException) do
        ShardFile.from_yaml(yaml)
      end
    end
  end

  describe "#dev_dependency_names" do
    it "returns development dependency names" do
      yaml = <<-YAML
        name: my-shard
        version: 0.1.0
        dependencies:
          kemal:
            github: kemalcr/kemal
        development_dependencies:
          ameba:
            github: crystal-ameba/ameba
          spec2:
            github: waterlink/spec2.cr
        YAML

      shard = ShardFile.from_yaml(yaml)
      dev_names = shard.dev_dependency_names

      dev_names.size.should eq 2
      dev_names.includes?("ameba").should be_true
      dev_names.includes?("spec2").should be_true
      dev_names.includes?("kemal").should be_false
    end

    it "returns empty set when no development_dependencies" do
      yaml = <<-YAML
        name: my-shard
        version: 0.1.0
        YAML

      shard = ShardFile.from_yaml(yaml)
      shard.dev_dependency_names.should be_empty
    end
  end
end
