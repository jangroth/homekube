# Homekube

A vanilla Kubernetes cluster on four Raspberry Pis, run as a home lab that also hosts AI agents doing coding work.

## Agents

**Hermes**:
The long-running assistant that hands coding tasks to workspaces.
_Avoid_: the agent

**OpenCode**:
The coding agent that runs a task inside a workspace.
_Avoid_: the agent

**Workspace**:
A Coder workspace: an isolated pod where one coding task runs.
_Avoid_: sandbox, dev box

**Task**:
One issue handed to one workspace, from claim to PR or failure.
_Avoid_: job, run

**Template**:
The Coder template that defines what a workspace is.

**Routine**:
A scheduled Claude Code agent in the cloud that implements issues.

**Executor**:
The agent that takes an issue: Hermes or a routine.
_Avoid_: worker, runner

**Routing label**:
The `agent:*` label that names an issue's executor.

**Bakery**:
The external repo `homekube-bakery` that builds the workspace and agent images.

## Egress

**Aperture**:
The LLM gateway on the tailnet; it holds the upstream model keys.
_Avoid_: AI gateway, LLM proxy

**Agent Vault**:
The in-cluster HTTPS proxy that injects credentials into an agent's outbound requests, so the agent never holds them.
_Avoid_: the proxy, vault

**Bundle**:
A named set of services in Agent Vault; a session is granted on exactly one bundle.

**Service**:
In Agent Vault, a host together with the credential injected for it.

**Session**:
Agent Vault's grant on one bundle.

**Session token**:
The credential a workspace or Hermes presents to Agent Vault to use a session.
_Avoid_: session (for the credential)

## Secrets

**Infisical**:
The self-hosted secret store that holds every cluster secret except bootstrap secrets.

**Bootstrap secret**:
A secret that stays sealed because the cluster needs it before Infisical is running, or to raise an alert when Infisical is down.
_Avoid_: sealed secret (for the category)

**Cluster secret**:
A secret in Infisical that a pod must hold itself, so it is synced into the cluster.
_Avoid_: Kubernetes secret (for the category)

**Brokered credential**:
A credential in Infisical that Agent Vault injects into an agent's outbound requests, so the agent never holds it.
_Avoid_: agent secret

**Upstream model key**:
An LLM provider's API key; it lives in Aperture and is backed up in the owner's password manager, never in Infisical or the cluster.
_Avoid_: LLM key, OpenRouter key (for the category)

**Machine identity**:
A workload's identity in Infisical. Each app reads its cluster secrets with its own, bound to one service account in its namespace and to that app's project.
_Avoid_: Infisical user, service identity
