# Configuration

[Data Guard MCP Server](README.md) > Configuration

Everything is optional; the image works as shipped. Set environment variables
on the runtime with `--environment-variables` on `create-agent-runtime` or
`update-agent-runtime`, or in the AgentCore console.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `DG_TOKEN_KEY` | unset | Default key for `hash` and `encrypt`, and so for `gdpr_basic`, when a call passes no `key`. Keep it in a secret manager, apart from redacted output |
| `DG_AUDIT_LOG` | off | One JSON line per call. `stderr` (CloudWatch under AgentCore) or `stdout`; any other value is a file path. See [Audit log](#audit-log) |
| `DG_MAX_INPUT_BYTES` | 16 MiB in version 0.1.0 | Largest input accepted, checked before reading. Scanning time grows with size, so keep it modest |
| `DG_SCRATCH_DIR` | `/tmp/data-guard` | Where `redact_data` results over 256 KiB are written. Normally leave it |
| `DG_LOG_REFUSALS` | off | `1` logs one line per refused call, to confirm a failing call arrived |

Example:

```bash
--environment-variables '{"DG_AUDIT_LOG": "stderr", "DG_TOKEN_KEY": "<from your secret manager>"}'
```

`DG_ALLOW_RAW_PREVIEW` exists for local rule debugging and makes previews show
real values. **Never set it on a deployed runtime.**

## Audit log

With `DG_AUDIT_LOG` set, every data-touching call writes one line: counts,
hashes, rule names and settings, never any part of the document.

```json
{"ts":"2026-08-25T09:57:56.030Z","request_id":"677914e5612a4e08a530b746497306f4",
 "tool":"redact_data","policy":"default","document_kind":"text","min_confidence":0.5,
 "input_sha256":"6551cbf3...","input_bytes":15,"origin":"inline_text",
 "total_redactions":1,"by_entity_type":{"US_SSN":1},"by_category":{"pii":1},
 "by_strategy":{"label":1},"by_source":{"detected":1,"model":0,"caller":0},
 "delivery":"inline_text","reversible":false}
```

- `request_id` is also in the tool response, so a response and its record can
  be matched later.
- If the line cannot be written, the call fails rather than succeeding without
  a record.

## Health check

`GET /healthz` redacts a synthetic record and confirms nothing leaked. It
catches a server that is up but not redacting, which a plain liveness check
would miss.

```json
{"status": "ok", "detected": ["AWS_ACCESS_KEY_ID", "PERSON", "US_SSN"], "leaked_count": 0}
```

Any other `status`, or a `503`, is an outage even though the process runs.

## Upgrading

Each version has its own image tag on the fulfillment page; `latest` is not
used. To upgrade, point the runtime at the new image:

```bash
aws bedrock-agentcore-control update-agent-runtime --region "$AWS_REGION" \
  --agent-runtime-id <agentRuntimeId> \
  --agent-runtime-artifact "{\"containerConfiguration\": {\"containerUri\": \"$NEW_IMAGE_URI\"}}" \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/bedrock-agentcore-role" \
  --network-configuration '{"networkMode": "PUBLIC"}'
```

Pass your environment variables again: the update replaces the configuration.
