# AI agents and MCP

[Data Guard API](README.md) > AI agents and MCP

Two ways to give an agent Data Guard as tools. Both use your subscription and
are billed like the REST API.

| | [Hosted MCP server](#hosted-mcp-server) | [AgentCore Gateway](#amazon-bedrock-agentcore-gateway) |
|---|---|---|
| Use it from | Claude, VS Code, Copilot Studio, any MCP client | Agents behind an Amazon Bedrock AgentCore Gateway |
| Setup | Paste a URL and your key | Create a gateway target from the OpenAPI schema |
| Who holds the key | Your MCP client's configuration | The gateway; it never reaches the model |

## Hosted MCP server

| | |
|---|---|
| Endpoint | `https://api.llmlinq.com/data-guard/mcp` |
| Transport | MCP streamable HTTP, stateless, JSON responses |
| Authentication | your API key: `Authorization: Bearer llq_live_...` or `X-Api-Key: llq_live_...` |

Most clients take a configuration like this:

```json
{
  "mcpServers": {
    "data-guard": {
      "type": "http",
      "url": "https://api.llmlinq.com/data-guard/mcp",
      "headers": { "Authorization": "Bearer llq_live_..." }
    }
  }
}
```

Claude Code:

```bash
claude mcp add --transport http data-guard https://api.llmlinq.com/data-guard/mcp \
  --header "Authorization: Bearer $DG_API_KEY"
```

Keep the key out of shared configuration files; most clients can read it from
an environment variable.

### Tools

| Tool | Same as | What it does |
|---|---|---|
| `list_detectors` | `GET /detectors` | Entity types, packs, strategies. Free |
| `scan_data` | `POST /scan` | Find sensitive values, change nothing |
| `redact_data` | `POST /redact` | Redact under a policy, with a receipt |
| `restore_data` | `POST /restore` | Reverse an `encrypt` redaction |
| `check_policy` | `POST /check` | Pass or fail against a compliance pack |

Parameters and results are the same as the [REST API](api-reference.md), with
two rules:

- **Inline input only**: `text` or `base64_data`. A `path` is refused; the
  server cannot read files on your machine.
- **Pass `key` yourself** for the `hash` and `encrypt` strategies, `gdpr_basic`
  and `restore_data`. It is never stored.

A good instruction for the agent: call `scan_data` first, then `redact_data`
with the pack that matches your regime.

A refused tool call (a bad parameter, a wrong restore key) comes back as a tool
error with the API's message. A key or subscription problem is an HTTP `401` or
`403` on the request, so your client shows it as an authentication failure.

## Amazon Bedrock AgentCore Gateway

A gateway turns the REST endpoints into MCP tools and holds the API key so it
never reaches the model.

1. **Store the key.** In the AgentCore console, open **Identity** and create an
   **API key** credential provider holding your `llq_live_...` key.
2. **Create a gateway** with the inbound authorization your agents already use
   (JWT or IAM).
3. **Download the schema.** The target takes it inline or from `s3://`, not from
   an HTTPS URL:
   ```bash
   curl -s -o openapi-agentcore.json \
     https://api.llmlinq.com/data-guard/v1/openapi-agentcore.json
   ```
4. **Add a target:**

   | Field | Value |
   |---|---|
   | Target protocol | **MCP target** |
   | Target type | **REST API** (`OPEN_API_SCHEMA`), **not** "MCP server" |
   | Schema | the contents of `openapi-agentcore.json`, inline (or from S3) |
   | Outbound auth | the credential provider from step 1, location **HEADER**, header name `Authorization` |

Your agent then sees `<target>___scan`, `<target>___redact`,
`<target>___restore`, `<target>___check` and `<target>___listDetectors`.

Good to know:

- Use `openapi-agentcore.json`, not `openapi.yaml`: the gateway rejects the
  `allOf` the readable spec uses.
- The gateway drops any argument the schema does not declare.
- The target keeps its own copy of the schema. After an API release that adds
  fields, download and paste it again. `update-gateway-target` replaces the
  whole target, so include the credential configuration or the key detaches.
- The `Bearer` prefix is optional; the API accepts the key either way.

Problems: [Troubleshooting](troubleshooting.md#ai-agents-and-mcp).
