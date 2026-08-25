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

### 4.3 Client setup (Python)

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

_id = 0

def call(method, params=None):
    global _id
    _id += 1
    body = json.dumps({"jsonrpc": "2.0", "id": _id, "method": method,
                       "params": params or {}})
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

def tool(name, **arguments):
    """Call an MCP tool and return its parsed JSON result."""
    res = call("tools/call", {"name": name, "arguments": arguments})
    return json.loads(res["result"]["content"][0]["text"])

# Discover tools
print(call("tools/list")["result"]["tools"])
```

The `tool` helper is used by every example in section 6.

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

No arguments. Returns `read` and `write` (the format lists), `binary_formats`
(the three that require `base64_data`), `aliases`, and `schema_dialects`.

### 5.2 inspect_data

Cheap probe of a dataset. Call this first when the format is unknown.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `preview_rows` | integer | `5` | rows to include in the preview (0-100) |

Returns: `detected_format`, `encoding`, `delimiter`, `has_header`, `confidence`,
`bytes`, `origin`, and (when parseable) `rows`, `columns`, `dtypes`, `preview`.
Here `columns` is the list of column *names*; on `convert_data` it is a count.

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

## 6. Examples

These use the `tool` helper from section 4.3. Responses are abridged to the
fields each example is about.

### 6.1 Check what the server supports

```python
tool("list_supported_formats")
# -> {"read":  ["avro","csv","excel","json","ndjson","parquet","tsv","xml","yaml"],
#     "write": ["avro","csv","excel","json","ndjson","parquet","tsv","xml","yaml"],
#     "binary_formats": ["avro","excel","parquet"],
#     "aliases": {"jsonl": "ndjson", "json-lines": "ndjson", "yml": "yaml",
#                 "xlsx": "excel", "xls": "excel", "parq": "parquet"},
#     "schema_dialects": ["json_schema","sql","avro","pydantic"]}
```

All nine formats both read and write, so any pair is a valid conversion.

### 6.2 Inspect before converting

Call this first when you do not control the input. It is cheap, and a low
`confidence` tells you to pass `from_format` explicitly instead of guessing.

```python
tool("inspect_data", text="id	name
1	Alice
2	Bob
", preview_rows=2)
# -> {"detected_format": "tsv", "encoding": "ascii", "delimiter": "	",
#     "has_header": true, "confidence": 0.7, "bytes": 22, "origin": "inline_text",
#     "rows": 2, "columns": ["id", "name"],
#     "dtypes": {"id": "Int64", "name": "String"},
#     "preview": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}
```

Use `preview_rows=0` for metadata only, with no row data in the model's context.

### 6.3 Convert between text formats

```python
# CSV to JSON
tool("convert_data", to_format="json", text="id,name
1,alice
2,bob
")
# -> {"source_format": "csv", "target_format": "json", "rows": 2, "columns": 2,
#     "delivery": "inline_text", "bytes": 47,
#     "text": "[{\"id\":1,\"name\":\"alice\"},{\"id\":2,\"name\":\"bob\"}]"}

# JSON to NDJSON - the alias resolves, so target_format comes back as ndjson
tool("convert_data", to_format="jsonl", text='[{"id":1},{"id":2}]')
# -> {"target_format": "ndjson", "text": "{\"id\":1}
{\"id\":2}
"}

# A nested object is JSON-encoded into the cell, so nothing is lost
tool("convert_data", to_format="csv",
     text='[{"id":1,"user":{"name":"alice","geo":{"country":"DE"}}}]')
# -> {"text": "id,user
1,\"{\"\"name\"\": \"\"alice\"\", \"\"geo\"\": {\"\"country\"\": \"\"DE\"\"}}\"
"}
```

Note that the object is kept in one `user` column rather than flattened into
`user.name` and `user.geo.country`.

> **List-valued fields do not survive CSV, TSV, or Excel.** They are written as
> an internal debug representation instead of JSON, and cannot be read back.
> Use Parquet, Avro, JSON, NDJSON, or YAML for data containing lists - see
> section 8.

### 6.4 Binary formats

Binary goes in as `base64_data` and comes back as `base64_data`.

```python
import base64

res = tool("convert_data", to_format="parquet", text="id,name
1,alice
")
# -> {"target_format": "parquet", "rows": 1, "columns": 2,
#     "delivery": "inline_base64", "bytes": 821, "base64_data": "UEFSMR..."}
open("out.parquet", "wb").write(base64.b64decode(res["base64_data"]))

blob = base64.b64encode(open("out.parquet", "rb").read()).decode()
tool("convert_data", to_format="json", base64_data=blob)
# -> {"source_format": "parquet", "rows": 1, "text": "[{\"id\":1,\"name\":\"alice\"}]"}
```

### 6.5 Source options

Overrides for inputs auto-detection gets wrong.

```python
# Semicolon-delimited, Latin-1
tool("convert_data", to_format="json", text=EXPORT,
     from_format="csv", delimiter=";", encoding="latin-1")

# No header row - columns are named positionally, starting at 1
tool("convert_data", to_format="json", text="1,alice
", has_header=False)
# -> {"text": "[{\"column_1\":1,\"column_2\":\"alice\"}]"}

# A named Excel sheet
tool("convert_data", to_format="csv", base64_data=xlsx, sheet="Q3 Actuals")

# The repeated XML element that represents a row
tool("convert_data", to_format="csv", text=XML, xml_record_tag="item")
# -> {"text": "sku,price
A-1,9.99
B-2,14.50
"}
```

`xml_record_tag` is rarely needed - detection picks the right element on its
own for ordinary documents. Pass it when several repeated elements compete.

### 6.6 Infer a schema

```python
CSV = "id,name,signed_up
1,alice,2024-03-01
"

tool("infer_schema", text=CSV, dialect="sql", table_name="users")
# -> {"source_format": "csv", "dialect": "sql", "rows_sampled": 1,
#     "schema": 'CREATE TABLE users (
  "id" BIGINT NOT NULL,

#                "name" TEXT NOT NULL,
  "signed_up" DATE NOT NULL
);'}
```

`dialect` also takes `json_schema` (the default, returning an object schema),
`avro`, and `pydantic`. Types are inferred from the rows actually read, and
`rows_sampled` reports how many that was. The dialects do not always agree on
the same column - a date reaches SQL as `DATE` but Pydantic as `str` - so check
the output before generating a table from it.

### 6.7 Large files

Pass `path` to read a file already on the container filesystem. Results over
256 KiB are written to the scratch directory and only the path comes back, so a
large conversion never floods the model's context.

```python
res = tool("convert_data", to_format="json",
           path="/tmp/uploads/events.ndjson", from_format="ndjson")
# -> {"source_format": "ndjson", "rows": 60000, "columns": 4,
#     "delivery": "path", "bytes": 6390373,
#     "path": "/tmp/format-converter/converted.json"}

# the returned path feeds straight into the next call
tool("infer_schema", path=res["path"], dialect="sql", table_name="events")
```

The threshold applies to the *result*, not the input: a 6 MB NDJSON file
converted to Parquet compresses to well under 256 KiB and comes back inline.
Read `delivery` rather than assuming, and take the output from `text`,
`base64_data`, or `path` accordingly.

---

## 7. Configuration

All settings are optional - the container ships with working defaults. Override
them only if needed, as environment variables in the delivery option or runtime
configuration.

| Variable | Default | Purpose |
|---|---|---|
| `FC_MAX_INPUT_BYTES` | `536870912` (512 MiB) | Reject inputs larger than this, instead of risking out-of-memory. This is the main tunable. |
| `FC_SCRATCH_DIR` | `/tmp/format-converter` (pre-set in the image) | Where large (over 256 KiB) results are written. Already configured and writable; normally leave it as-is. |

---

## 8. Limits and behavior

- Maximum input size defaults to 512 MiB (`FC_MAX_INPUT_BYTES`). Oversized
  inputs are rejected with a clear error.
- Data is processed in memory; for very large files, prefer splitting the input
  or raising the limit within your container's memory.
- Deeply nested JSON/XML is normalized to tabular rows. A nested **object** in a
  cell of a flat format (CSV, TSV, Excel) is JSON-encoded, so nothing is lost.
- **Known issue: a list-valued field converted to CSV, TSV, or Excel is written
  as an internal debug representation rather than JSON**, which is not
  round-trippable. Convert such data to Parquet, Avro, JSON, NDJSON, or YAML,
  all of which preserve lists correctly.
- The server is stateless: every request is independent.

---

## 9. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Runtime never reaches READY | Check the execution role can pull the image and write logs; review CloudWatch logs under `/aws/bedrock-agentcore/`. |
| 403 / signature errors when calling | Ensure SigV4 signing uses service `bedrock-agentcore` and your IAM principal is allowed to invoke the runtime. |
| "Input too large" | Input exceeds `FC_MAX_INPUT_BYTES`; raise it or split the input. |
| "Could not detect source format" | Pass `from_format` explicitly. Single-column CSV/TSV is a common cause - there is no delimiter to find, so detection returns `unknown`. |
| "Unsupported target format" / "Unsupported source format" | The name is not one of the nine formats or their aliases; `list_supported_formats` returns both lists. |
| "Provide exactly one of text / base64_data / path" | Supply a single input argument. |
| "no matching sheet found" | The `sheet` name does not exist in the workbook. Convert without `sheet` to read the first one. |
| A list-valued column came back as `shape: (2,) Series...` | Known issue converting lists to CSV/TSV/Excel - see section 8. Use Parquet, Avro, JSON, NDJSON, or YAML instead. |

---

## 10. Support

For help with this product, contact the seller through the **Support** link on
the product's AWS Marketplace listing page.
