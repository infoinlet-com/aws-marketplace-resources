# Troubleshooting

[Data Guard API](README.md) > Troubleshooting

Every error code is also in the [API reference](api-reference.md#errors).

## Subscribing

| Problem | Fix |
|---|---|
| "We could not confirm that subscription" on the setup page | The setup link is single-use and expires. Start again from **Set up your account** in the AWS Marketplace console |
| Setup says the AWS account is linked to another account | Sign in as that account, or contact support |
| Lost the API key | Rotate it on the [configure page](https://cloud.llmlinq.com/aws/data-guard/configure). It cannot be recovered, only replaced |

## Calling the API

| Problem | Fix |
|---|---|
| `401 api_key_required` | Send `Authorization: Bearer llq_live_...` or `X-Api-Key` |
| `401 invalid_api_key` | The key was rotated or mistyped. Copy the current one from the configure page |
| `403 subscription_inactive` | Pending, ended or cancelled. Check AWS Marketplace and the configure page |
| `403 trial_limit_reached` | The trial is used up. [Subscribe](billing.md#free-trial); the key stays the same |
| `400 unsupported_parameters` naming `path` | Files are not read over HTTP. Send the content as `text` or `base64_data` |
| `400` "Input too large" | Over 2 MiB. Split the document |
| `413 result_too_large` | The result is over 256 KiB. Split the document |
| `429` | Over the rate limit. Retry with exponential backoff |
| `500` | Retry. If it persists, contact support |

## Redaction

| Problem | Fix |
|---|---|
| `400` "The 'hash' strategy requires a key" | Pass `key`. `gdpr_basic` uses `hash`, so it needs one too |
| `400` "No encrypted placeholders were found" | `/restore` only reverses `encrypt` output (`<US_SSN:enc:...>`) |
| `400` "Could not restore ... no changes were applied" | Wrong key, or a placeholder was changed |
| Fewer findings than expected in JSON or CSV | It failed to parse and was scanned as text. Check `document_kind`; pass `kind` |
| A person's name was not redacted | Names with no title, label or field name are not detected. Pass it in `extra_spans` |
| Too many findings | Use `entity_types`, raise `min_confidence`, or pick a narrower pack. `strict_all` over-redacts on purpose |
| `document_truncated: true` | The document was only partly examined. Split it |

## AI agents and MCP

| Problem | Fix |
|---|---|
| MCP client cannot connect, or reports an auth error | Check the header on `https://api.llmlinq.com/data-guard/mcp`: `Authorization: Bearer llq_live_...` |
| MCP tool error naming `path` | The hosted server takes `text` or `base64_data` only |
| Gateway: `HTTP 404 to the initialize handshake` | Target type is "MCP server". Recreate it as **REST API** |
| Gateway: `401 api_key_required` in a tool result | Attach the credential provider to the target, location HEADER, header `Authorization` |
| Gateway: a new field is ignored | The target keeps a copy of the schema. [Paste the new one](ai-agents.md#amazon-bedrock-agentcore-gateway) |

## Contact support

Email **contact@infoinlet.com** with your AWS account ID and, for a specific
call, its `request_id` (or the error code and time). We cannot see your
documents, so that is how we trace a call. Never send your API key, redaction
keys or real sensitive values.
