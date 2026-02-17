require "spec"
require "../src/shard/shard_lock_file"

describe ShardLockFile do
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
