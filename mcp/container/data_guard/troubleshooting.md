# Troubleshooting

[Data Guard MCP Server](README.md) > Troubleshooting

## Deploying

| Problem | Fix |
|---|---|
| Runtime never reaches `READY` | The role cannot pull the image or write logs. Check the [permissions](getting-started.md#2-attach-permissions) and the CloudWatch logs under `/aws/bedrock-agentcore/runtimes/` |
| Image pull is denied | Your account must be subscribed to this product, and the image URI must come from your fulfillment page |
| `/healthz` is `degraded` or `503` | The engine is not redacting. Do not send traffic; check the logs and redeploy |

## Calling the server

| Problem | Fix |
|---|---|
| `403` or a signature error | Sign with SigV4, service `bedrock-agentcore`, and allow your principal to invoke the runtime |
| `404` | URL-encode the whole runtime ARN in the endpoint, `:` and `/` included |
| "Provide exactly one of text / base64_data / path" | Send a single input argument |
| "Input too large" | Over `DG_MAX_INPUT_BYTES`. Split the input |
| `path` with `s3://` fails | The image does not read S3. Fetch the object yourself and pass `text` or `base64_data` |

## Redaction

| Problem | Fix |
|---|---|
| "The 'hash' strategy requires a key" | Pass `key`, or set `DG_TOKEN_KEY`. `gdpr_basic` uses `hash` too |
| "No encrypted placeholders were found" | `restore_data` only reverses `encrypt` output (`<US_SSN:enc:...>`) |
| Restore fails | Wrong key, or a placeholder was changed. Nothing partial is returned |
| Fewer findings than expected in JSON or CSV | It failed to parse and was scanned as text. Check `document_kind`; pass `kind` |
| A person's name was not redacted | Names with no title, label or field name are not detected. Pass it in `extra_spans` |
| Too many findings | Use `entity_types`, raise `min_confidence`, or pick a narrower pack. `strict_all` over-redacts on purpose |
| `document_truncated: true` | The document was only partly examined. Split it |

## Contact support

Email **contact@infoinlet.com** with your AWS account ID, the image version,
and for a specific call its `request_id`. The server sends us nothing, so we
cannot see your calls. Never send keys or real sensitive values.
