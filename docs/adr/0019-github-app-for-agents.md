# Agents reach GitHub through a GitHub App

Agents use the GitHub App `homekube-agent`, installed only on the repos an agent may work on, so its installation tokens are scoped per repo and per permission; a collaborator's token on a personal account cannot be. Its PRs are authored by `homekube-agent[bot]`, and each installed repo's default-branch ruleset requires a PR and the owner's approval, with no bypass for the App.

## Considered Options

- **Machine user with a PAT**: rejected; its token reaches every repo it collaborates on, with the same permissions everywhere.
