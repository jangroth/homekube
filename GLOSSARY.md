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

**Template**:
The Coder template that defines what a workspace is.

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
