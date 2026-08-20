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

    it "leaves the version nil for a path dependency that has none" do
      yaml = <<-YAML
        version: 2.0
        shards:
          local_shard:
            path: /path/to/shard
        YAML

      lock_file = ShardLockFile.from_yaml(yaml)
      lock_file.shards.size.should eq(1)

      shard = lock_file.shards["local_shard"]
      shard.path.should eq("/path/to/shard")
      shard.version.should be_nil
      shard.commit.should be_nil
    end

    it "parses the remaining shards resolvers" do
      yaml = <<-YAML
        version: 2.0
        shards:
          bb:
            bitbucket: team/bbrepo
            version: 1.2.3
          cb:
            codeberg: team/cbrepo
            version: 2.0.0
          hgdep:
            hg: https://hg.example.com/repo
            version: 0.5.0
          fossildep:
            fossil: https://fossil.example.com/repo
            version: 0.6.0
        YAML

      shards = ShardLockFile.from_yaml(yaml).shards
      shards["bb"].bitbucket.should eq("team/bbrepo")
      shards["cb"].codeberg.should eq("team/cbrepo")
      shards["hgdep"].hg.should eq("https://hg.example.com/repo")
      shards["fossildep"].fossil.should eq("https://fossil.example.com/repo")
    end

    it "extracts the commit SHA shards embeds in a git version" do
      yaml = <<-YAML
        version: 2.0
        shards:
          spdx:
            git: https://github.com/hahwul/spdx.cr.git
            version: 0.1.0+git.commit.21ac950936830412628cbf631bf48ece6dce9a48
          tagged:
            git: https://github.com/o/r.git
            version: 1.2.3
        YAML

      shards = ShardLockFile.from_yaml(yaml).shards
      shards["spdx"].commit.should eq("21ac950936830412628cbf631bf48ece6dce9a48")
      # A plain semver is the tag itself, not a commit.
      shards["tagged"].commit.should be_nil
    end

    it "parses the git reference keys of a version 1.0 lock file" do
      # shards still reads `version: 1.0` lock files, whose entries are parsed
      # as plain dependencies and so name their reference directly rather than
      # folding it into `version`.
      yaml = <<-YAML
        version: 1.0
        shards:
          pinned:
            github: crystal-ameba/ameba
            commit: 0f4b2d5a1c9e7f3b8a6d4c2e0f1a3b5c7d9e1f20
          tagged:
            github: kemalcr/kemal
            tag: v1.4.0
          tracked:
            git: https://github.com/o/r.git
            branch: main
        YAML

      shards = ShardLockFile.from_yaml(yaml).shards
      shards["pinned"].commit.should eq("0f4b2d5a1c9e7f3b8a6d4c2e0f1a3b5c7d9e1f20")
      shards["pinned"].version.should be_nil
      shards["tagged"].tag.should eq("v1.4.0")
      shards["tagged"].commit.should be_nil
      shards["tracked"].branch.should eq("main")
      shards["tracked"].commit.should be_nil
      shards["tracked"].tag.should be_nil
    end

    it "prefers an explicit commit key over one embedded in the version" do
      yaml = <<-YAML
        version: 1.0
        shards:
          both:
            github: o/r
            version: 0.1.0+git.commit.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        YAML

      ShardLockFile.from_yaml(yaml).shards["both"].commit
        .should eq("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
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
