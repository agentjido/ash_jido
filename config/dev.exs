import Config

config :git_hooks, auto_install: false

config :git_ops,
  mix_project: AshJido.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/agentjido/ash_jido",
  manage_mix_version?: true,
  github_handle_lookup?: false,
  version_tag_prefix: "v"
