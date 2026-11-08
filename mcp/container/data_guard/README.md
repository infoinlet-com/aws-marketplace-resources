# Data Guard MCP Server

An MCP server that finds and redacts PII, PHI, financial data and secrets in
text, JSON, NDJSON, YAML and CSV, before they reach a log, a third party or a
model's context.

- **Runs in your AWS account** on Amazon Bedrock AgentCore Runtime. Your data
  stays there; nothing is sent to us.
- **Deterministic**: checksums, patterns, field-name rules and word lists, no ML
  model. Every finding names the rule behind it.
- **Never echoes what it protects**: findings carry offsets and a masked
  preview, never the value.
- **64 entity types**, six compliance policy packs, seven redaction strategies.
- ARM64 container, stateless, MCP streamable HTTP on port `8000`.

## Guides

**[Getting started](getting-started.md)** - **Start here.** Deploy to AgentCore
Runtime and make your first tool call, in about 15 minutes.

**[Examples](examples.md)** - A Python client and code to copy: scan, redact,
structured documents, compliance gates, reversible redaction, large files.

**[Tools reference](tools-reference.md)** - The five tools, their arguments
and results.

**[Policies and strategies](policies.md)** - Which pack to pick, what each
redaction strategy leaves behind, and handling keys.

**[Configuration](configuration.md)** - Environment variables, the audit log,
the health check, and upgrading.

**[Troubleshooting](troubleshooting.md)** - Common problems and their fix.

**[Data handling and limits](data-handling.md)** - What the server does and
does not claim, and known detection limits. For security and compliance
reviews.

## Try it first

This listing has no free trial. The hosted
[Data Guard API](https://aws.amazon.com/marketplace/pp/prodview-i4qrny5rdr3o2)
runs the same engine and has a 30-day free trial, including the same five tools
over a [hosted MCP server](../../../api/saas/data_guard/ai-agents.md). It runs in
our AWS account, not yours, so evaluate it with sample data.

## Support

**contact@infoinlet.com** - we reply within one business day, Monday to Friday.
