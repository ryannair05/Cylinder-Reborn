---
name: hopper-implementation-evidence
description: "Use this skill first when a prompt needs implementation evidence from Hopper 6 MCP: app or framework procedures, strings, xrefs, selectors, assembly, pseudocode, private UIKit layout, animation internals, or binary behavior. Reuse open documents and keep queries targeted."
---

# Hopper Implementation Evidence

Use registered `HopperMCPServer` directly. Prefer this over repeated simulator captures for implementation, animation, layout, or private class behavior.

## Workflow

1. Call MCP `list_documents` first. If the target is already open, select it; do not reopen/import it.
2. Import with Hopper CLI only when the needed binary/framework is absent, then wait for analysis.
3. Search one symbol/string family, inspect one procedure/address at a time, and summarize only concrete findings.

## Defaults

- Hopper is licensed; do not assume a 30-minute limit.
- Prefer direct MCP tools over shell helpers or wrapper scripts.
- Open/import only one missing target.
- Do not use `open -a Hopper <binary>` for imports; it can create blank documents.
- Avoid concurrent MCP calls and broad `search_strings`.
- For large methods, inspect address/assembly before asking for heavier procedure metadata or pseudocode.

## Startup Readiness

- Keep the project MCP registration pointed at `.codex/hopper-mcp-launcher.zsh`; do not replace it with the raw `HopperMCPServer` executable. The launcher prevents Hopper 6.4.3's startup race by waiting for the `com.cryptic-apps.ExternalAPI` Mach service before starting the STDIO server.
- Do not invoke the launcher manually from an active Codex session. Codex owns its STDIO lifetime and starts the registered launcher when the session initializes.
- Service readiness does not mean a newly opened or imported Hopper document has finished loading. If the user says a document was just added and the first `list_documents` result is missing it, wait briefly and retry `list_documents` sequentially with a small bounded retry count before concluding that it is unavailable.

## Transport Failure

- Treat `Transport closed` as a terminal failure for the current Codex session.
- Do not retry the Hopper MCP call, manually relaunch Hopper, or start another `HopperMCPServer` in that session; repeated STDIO connection attempts can strand duplicate helpers.
- Report that Codex must be restarted before Hopper MCP is used again. If cleanup is requested, inspect exact-name `HopperMCPServer` processes, terminate only confirmed stale helpers, and verify the exact-name count returns to zero.
