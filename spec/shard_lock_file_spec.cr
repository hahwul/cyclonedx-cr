require "spec"
require "../src/shard/shard_lock_file"

describe ShardLockFile do
  describe "parsing" do
    it "parses a shard.lock file with git dependency" do
      yaml = <<-YAML
        version: 2.0
        shards:
          ameba:
            git: https://github.com/crystal-ameba/ameba.git
            version: 1.6.4
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      ameba = lock_file.shards["ameba"]
      ameba.version.should eq("1.6.4")
      ameba.git.should eq("https://github.com/crystal-ameba/ameba.git")
      ameba.github.should be_nil
      ameba.path.should be_nil
    end

    it "parses a shard.lock file with github dependency" do
      yaml = <<-YAML
        version: 2.0
        shards:
          my_shard:
            github: owner/repo
            version: 0.1.0
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      shard = lock_file.shards["my_shard"]
      shard.version.should eq("0.1.0")
      shard.github.should eq("owner/repo")
      shard.git.should be_nil
      shard.path.should be_nil
    end

    it "parses a shard.lock file with path dependency" do
      yaml = <<-YAML
        version: 2.0
        shards:
          local_shard:
            path: /path/to/shard
            version: 0.0.1
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      shard = lock_file.shards["local_shard"]
      shard.version.should eq("0.0.1")
      shard.path.should eq("/path/to/shard")
      shard.git.should be_nil
      shard.github.should be_nil
    end

    it "parses an empty shards section" do
      yaml = <<-YAML
        version: 2.0
        shards: {}
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.should be_empty
    end

    it "parses a file with missing version field (implicit)" do
      yaml = <<-YAML
        shards:
          ameba:
            git: https://github.com/crystal-ameba/ameba.git
            version: 1.6.4
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)
    end

    it "ignores extra fields" do
      yaml = <<-YAML
        version: 2.0
        extra_field: "some value"
        shards:
          ameba:
            git: https://github.com/crystal-ameba/ameba.git
            version: 1.6.4
            extra_entry_field: "ignored"
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)
      lock_file.shards["ameba"].version.should eq("1.6.4")
    end
    it "parses a shard.lock file with git dependency" do
      yaml = <<-YAML
        version: 2.0
        shards:
          ameba:
            git: https://github.com/crystal-ameba/ameba.git
            version: 1.6.4
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      entry = lock_file.shards["ameba"]
      entry.version.should eq("1.6.4")
      entry.git.should eq("https://github.com/crystal-ameba/ameba.git")
      entry.github.should be_nil
      entry.path.should be_nil
    end

    it "parses a shard.lock file with github dependency" do
      yaml = <<-YAML
        version: 2.0
        shards:
          my_shard:
            github: owner/repo
            version: 0.1.0
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      entry = lock_file.shards["my_shard"]
      entry.version.should eq("0.1.0")
      entry.github.should eq("owner/repo")
      entry.git.should be_nil
      entry.path.should be_nil
    end

    it "parses a shard.lock file with path dependency" do
      yaml = <<-YAML
        version: 2.0
        shards:
          local_shard:
            path: /path/to/shard
            version: 0.0.1
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      entry = lock_file.shards["local_shard"]
      entry.version.should eq("0.0.1")
      entry.path.should eq("/path/to/shard")
      entry.git.should be_nil
      entry.github.should be_nil
    end

    it "parses a shard.lock file with multiple dependencies" do
      yaml = <<-YAML
        version: 2.0
        shards:
          ameba:
            git: https://github.com/crystal-ameba/ameba.git
            version: 1.6.4
          my_shard:
            github: owner/repo
            version: 0.1.0
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(2)

      lock_file.shards["ameba"].version.should eq("1.6.4")
      lock_file.shards["my_shard"].version.should eq("0.1.0")
    end

    it "handles empty shards list" do
      yaml = <<-YAML
        version: 2.0
        shards: {}
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.empty?.should be_true
    end

    it "ignores top-level version field by default" do
      # YAML::Serializable ignores extra fields by default unless strict: true is set.
      # This test ensures that parsing succeeds despite the 'version' field not being in the model.
      yaml = <<-YAML
        version: 2.0
        shards:
          ameba:
            git: https://github.com/crystal-ameba/ameba.git
            version: 1.6.4
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)
    end
  end
end
