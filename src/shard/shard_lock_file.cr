require "yaml"

# Represents the structure of a `shard.lock` file.
# This file contains the resolved dependencies of the project.
class ShardLockFile
  include YAML::Serializable

  # A hash mapping shard names to their `ShardLockEntry` details.
  getter shards : Hash(String, ShardLockEntry) = {} of String => ShardLockEntry
end

# Represents a single entry within the `shards` section of a `shard.lock` file.
# It provides details about a specific dependency.
class ShardLockEntry
  include YAML::Serializable

  # `X.Y.Z+git.commit.<sha>` is what shards writes when the resolved commit is
  # not itself a released tag. The trailing SHA is the only value that actually
  # identifies the tree, so it is what a `pkg:github`/`gitlab`/`bitbucket` PURL
  # should carry — those PURL types define the version as a tag or a commit, and
  # the composite string is neither.
  GIT_COMMIT_VERSION = /\+git\.commit\.([0-9a-f]{7,40})\z/

  # The version of the locked dependency. Absent for `path:` entries (and some
  # other lock shapes), in which case it stays nil rather than being filled in
  # with a placeholder: no version is a fact, "unknown" is a fabrication.
  getter version : String?
  # The Git URL if the dependency is sourced from a Git repository.
  getter git : String?
  # The Mercurial repository URL.
  getter hg : String?
  # The Fossil repository URL.
  getter fossil : String?
  # The GitHub repository path (e.g., "owner/repo") if sourced from GitHub.
  getter github : String?
  # The GitLab repository path (e.g., "owner/repo") if sourced from GitLab.
  getter gitlab : String?
  # The Bitbucket repository path (e.g., "owner/repo").
  getter bitbucket : String?
  # The Codeberg repository path (e.g., "owner/repo").
  getter codeberg : String?
  # The local path if the dependency is a local path dependency.
  getter path : String?

  # The commit SHA embedded in `version`, when shards recorded one.
  def commit : String?
    @version.try(&.match(GIT_COMMIT_VERSION)).try(&.[1])
  end
end
