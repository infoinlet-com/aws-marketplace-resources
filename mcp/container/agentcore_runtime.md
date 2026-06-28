# Universal Data Format Converter (MCP Server) - Usage Guide

This guide explains how to deploy and use the **Universal Data Format Converter**,
an MCP (Model Context Protocol) server delivered as a container and hosted on
**Amazon Bedrock AgentCore Runtime**. You deploy it in your own AWS account, so
your data never leaves your boundary.

- Protocol: MCP over streamable HTTP (`POST /mcp`)
- Architecture: ARM64 (AWS Graviton), stateless, listens on port `8000`
- Tools: `list_supported_formats`, `inspect_data`, `convert_data`, `infer_schema`
- Formats: CSV, TSV, JSON, NDJSON, YAML, XML, Excel, Parquet, Avro

---

## 1. What this product does

It gives an AI agent reliable, deterministic data-format tooling - the kind of
work an LLM cannot do dependably on its own. The agent calls four tools to:

- Detect a dataset's format, encoding, delimiter, columns, and types
- Convert data between nine formats
- Infer a schema (JSON Schema, SQL DDL, Avro, or a Pydantic model)

Outputs are bounded so they never flood the model context, and oversized inputs
are rejected with a clear error instead of crashing.

---

## 2. Prerequisites

- An AWS account subscribed to this product in AWS Marketplace.
- Amazon Bedrock AgentCore available in your chosen Region (for example
  `us-east-1`).
- AWS CLI v2 installed and configured, or Python 3.11+ with `boto3`.
- IAM permissions to create an IAM role and call `bedrock-agentcore-control`
  and `bedrock-agentcore`.

---

## 3. Deploy to Amazon Bedrock AgentCore Runtime

You can deploy from the AgentCore console (select this product's container image)
or with the AWS CLI. The CLI flow below is fully reproducible.

Set shared variables:

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# The container image URI is provided on your AWS Marketplace fulfillment page
# after you subscribe. It looks like:
#   <registry>.dkr.ecr.<region>.amazonaws.com/<path>/data-format-converter-mcp:<version>
export IMAGE_URI="<paste-the-image-uri-from-your-fulfillment-page>"
```

### 3.1 Create an execution role

AgentCore assumes this role to pull the image and write logs.

```bash
cat > trust.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "bedrock-agentcore.amazonaws.com" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "aws:SourceAccount": "${ACCOUNT_ID}" },
      "ArnLike": { "aws:SourceArn": "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:*" }
    }
  }]
}
JSON

cat > perms.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow",
      "Action": ["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:BatchCheckLayerAvailability"],
      "Resource": "*" },
    { "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/bedrock-agentcore/*" },
    { "Effect": "Allow",
      "Action": ["bedrock-agentcore:GetWorkloadAccessToken","bedrock-agentcore:GetWorkloadAccessTokenForJWT","bedrock-agentcore:GetWorkloadAccessTokenForUserId"],
      "Resource": "*" }
  ]
}
JSON

aws iam create-role --role-name data-format-converter-mcp-role \
  --assume-role-policy-document file://trust.json --region "$AWS_REGION"
aws iam put-role-policy --role-name data-format-converter-mcp-role \
  --policy-name exec --policy-document file://perms.json
export ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/data-format-converter-mcp-role"
```

### 3.2 Create the agent runtime

```bash
cat > runtime.json <<JSON
{
  "agentRuntimeName": "data_format_converter_mcp",
  "agentRuntimeArtifact": { "containerConfiguration": { "containerUri": "${IMAGE_URI}" } },
  "roleArn": "${ROLE_ARN}",
  "networkConfiguration": { "networkMode": "PUBLIC" },
  "protocolConfiguration": { "serverProtocol": "MCP" }
}
JSON

aws bedrock-agentcore-control create-agent-runtime \
  --region "$AWS_REGION" --cli-input-json file://runtime.json
```

Note the returned `agentRuntimeId` and `agentRuntimeArn`.

### 3.3 Wait until READY

```bash
aws bedrock-agentcore-control get-agent-runtime \
  --region "$AWS_REGION" --agent-runtime-id <agentRuntimeId> \
  --query status --output text
```

When status is `READY`, the server is live.

---

## 4. Connect and invoke

### 4.1 Endpoint

The runtime exposes an MCP endpoint at:

```
https://bedrock-agentcore.<region>.amazonaws.com/runtimes/<url-encoded-runtime-arn>/invocations?qualifier=DEFAULT
```

URL-encode the full runtime ARN (encode `:` and `/`).

### 4.2 Authentication

By default the endpoint uses AWS IAM authentication. Sign each request with
AWS Signature Version 4 (SigV4), service name `bedrock-agentcore`. (If you
configured a JWT/OAuth authorizer instead, send a `Bearer` token.)

### 4.3 Example: list tools and run a conversion (Python)

```python
import json, urllib.parse, urllib.request
import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

REGION = "us-east-1"
ARN = "arn:aws:bedrock-agentcore:us-east-1:<account>:runtime/<runtime-id>"
creds = boto3.Session().get_credentials().get_frozen_credentials()
url = (f"https://bedrock-agentcore.{REGION}.amazonaws.com/runtimes/"
       f"{urllib.parse.quote(ARN, safe='')}/invocations?qualifier=DEFAULT")

def call(method, params, _id):
    body = json.dumps({"jsonrpc": "2.0", "id": _id, "method": method, "params": params})
    req = AWSRequest(method="POST", url=url, data=body,
                     headers={"Content-Type": "application/json",
                              "Accept": "application/json, text/event-stream"})
    SigV4Auth(creds, "bedrock-agentcore", REGION).add_auth(req)
    http = urllib.request.Request(url, data=body.encode(), headers=dict(req.headers), method="POST")
    text = urllib.request.urlopen(http, timeout=60).read().decode()
    for line in text.splitlines():
        if line.startswith("data: "):
            return json.loads(line[6:])
    return json.loads(text)

# Discover tools
print(call("tools/list", {}, 1)["result"]["tools"])

# Convert CSV to JSON
res = call("tools/call", {
    "name": "convert_data",
    "arguments": {"to_format": "json", "text": "id,name\n1,alice\n2,bob\n"},
}, 2)
print(res["result"]["content"][0]["text"])
# -> {... ,"text":"[{\"id\":1,\"name\":\"alice\"},{\"id\":2,\"name\":\"bob\"}]", ...}
```

### 4.4 Wiring it into an MCP-capable agent

Point your agent or framework's MCP client at the endpoint URL above using its
HTTP (streamable) transport, with SigV4 signing. The four tools then appear
automatically through `tools/list`.

---

## 5. Tools reference

Provide input data with **exactly one** of these arguments on any tool that
reads data:

- `text` - inline text (CSV, TSV, JSON, NDJSON, YAML, XML)
- `base64_data` - inline base64 for binary formats (Parquet, Avro, Excel)
- `path` - a file path on the container filesystem

Results return inline when small (under 256 KiB): text for text formats,
base64 for binary. Larger results are written to a scratch file and the path is
returned in the `path` field.

Supported format names: `csv`, `tsv`, `json`, `ndjson`, `yaml`, `xml`, `excel`,
`parquet`, `avro`. Accepted aliases: `jsonl` / `json-lines` (= ndjson), `yml`
(= yaml), `xlsx` / `xls` (= excel), `parq` (= parquet).

### 5.1 list_supported_formats

No arguments. Returns the readable/writable formats, aliases, and schema
dialects.

### 5.2 inspect_data

Cheap probe of a dataset. Call this first when the format is unknown.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `preview_rows` | integer | `5` | rows to include in the preview (0-100) |

Returns: `detected_format`, `encoding`, `delimiter`, `has_header`, `confidence`,
`bytes`, `origin`, and (when parseable) `rows`, `columns`, `dtypes`, `preview`.

### 5.3 convert_data

Convert data from one format to another.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `to_format` | string | required | target format |
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `from_format` | string | `auto` | source format, or auto-detect |
| `delimiter` | string | auto | override CSV/TSV delimiter |
| `encoding` | string | auto | override source text encoding |
| `has_header` | boolean | `true` | whether a CSV/TSV source has a header row |
| `sheet` | string/int | first | Excel sheet name or index |
| `xml_record_tag` | string | auto | repeated XML element to treat as a row |

Returns: `source_format`, `target_format`, `rows`, `columns`, `delivery`
(`inline_text` / `inline_base64` / `path`), `bytes`, and one of `text`,
`base64_data`, or `path`.

### 5.4 infer_schema

Infer a schema from sample data.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `dialect` | string | `json_schema` | `json_schema`, `sql`, `avro`, or `pydantic` |
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `from_format` | string | `auto` | source format, or auto-detect |
| `table_name` | string | `data` | name for the table/record/model |

Returns: `source_format`, `dialect`, `rows_sampled`, and `schema`.

---

## 6. Configuration

All settings are optional - the container ships with working defaults. Override
them only if needed, as environment variables in the delivery option or runtime
configuration.

| Variable | Default | Purpose |
|---|---|---|
| `FC_MAX_INPUT_BYTES` | `536870912` (512 MiB) | Reject inputs larger than this, instead of risking out-of-memory. This is the main tunable. |
| `FC_SCRATCH_DIR` | `/tmp/format-converter` (pre-set in the image) | Where large (over 256 KiB) results are written. Already configured and writable; normally leave it as-is. |

---

## 7. Limits and behavior

- Maximum input size defaults to 512 MiB (`FC_MAX_INPUT_BYTES`). Oversized
  inputs are rejected with a clear error.
- Data is processed in memory; for very large files, prefer splitting the input
  or raising the limit within your container's memory.
- Deeply nested JSON/XML is normalized to tabular rows; values that cannot fit a
  flat cell (CSV/Excel) are JSON-encoded.
- The server is stateless: every request is independent.

---

## 8. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Runtime never reaches READY | Check the execution role can pull the image and write logs; review CloudWatch logs under `/aws/bedrock-agentcore/`. |
| 403 / signature errors when calling | Ensure SigV4 signing uses service `bedrock-agentcore` and your IAM principal is allowed to invoke the runtime. |
| "Input too large" | Input exceeds `FC_MAX_INPUT_BYTES`; raise it or split the input. |
| "Could not detect source format" | Pass `from_format` explicitly. |
| "Provide exactly one of text / base64_data / path" | Supply a single input argument. |

---

## 9. Support

For help with this product, contact the seller through the **Support** link on
the product's AWS Marketplace listing page.
