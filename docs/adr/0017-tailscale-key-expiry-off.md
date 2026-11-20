# Tailscale node key expiry is off on darth and the pis

An expired node key silently cuts the management path (ADR-0001) to a node, so expiry is disabled in the Tailscale admin console. A node key that leaks stays valid until it is revoked by hand.

Replaces [Decision 070](../archive/decisions/DECISIONS.md).
