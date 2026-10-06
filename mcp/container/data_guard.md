# Data Guard (MCP Server) - Usage Guide

This guide explains how to deploy and use **Data Guard**, an MCP (Model Context
Protocol) server delivered as a container and hosted on **Amazon Bedrock
AgentCore Runtime**. You deploy it in your own AWS account, so your data never
leaves your boundary. Nothing phones home, and no key is ever stored server side.

- Protocol: MCP over streamable HTTP (`POST /mcp`)
- Architecture: ARM64 (AWS Graviton), stateless, listens on port `8000`
- Tools: `list_detectors`, `scan_data`, `redact_data`, `restore_data`, `check_policy`
- Document kinds: text, JSON, NDJSON, YAML, CSV
- Coverage: 64 entity types across PII, PHI, financial data, and secrets

---

## 1. What this product does

It gives an AI agent a deterministic way to find and remove sensitive values
before they reach a log, a third party, or another model's context. The five
tools let an agent:

- Discover what the server detects and which compliance packs exist
- Scan a document and report where sensitive values are, without changing it
- Redact a document under a named policy, returning an auditable receipt
- Reverse a reversible redaction, given the same key
- Gate a document against a compliance pack: pass or fail, with the violations

Detection is deterministic - regular expressions, checksums, curated word lists,
and field-name rules. There is no ML model in this image, so every finding names
the rule that produced it, and an auditor can follow it back to a check digit or
a dictionary entry.

Two properties hold on every call:

- **The server never echoes what it protects.** Findings return offsets and a
  masked preview, never the matched value.
- **It fails closed.** Strategies are validated before a single character is
  rewritten, a malformed caller span is refused rather than clamped, and a
  restore is all-or-nothing. A half-redacted document that reports success is
  exactly what the design prevents.

### 1.1 Try it free before subscribing

This container listing is a monthly subscription and has no free trial of its
own. We also offer the same detection engine as a hosted HTTPS API on AWS
Marketplace, the
[Data Guard API](https://aws.amazon.com/marketplace/pp/prodview-i4qrny5rdr3o2)
listing, and that listing includes a free trial. It runs the same detectors,
policy packs, and redaction strategies, so you can check detection quality on
your kind of data before deploying this container.

Two things to know when you evaluate that way:

- **The API is run by us, the same team that builds this container.** It keeps
  no copy of your documents and logs only that a call happened, never what was
  in it. Even so, it runs in our AWS account rather than yours, so we suggest
  evaluating with synthetic or already-approved sample data. When you deploy
  this container, everything stays inside your own account.
- **Tool names become endpoints**: `scan_data` is `POST /scan`, `redact_data` is
  `POST /redact`, and so on, with the same arguments except `path`, which the
  API does not accept.

Trial terms, allowance, and setup are in the
[Data Guard API usage guide](../../api/saas/data_guard.md#31-free-trial).

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

The product's fulfillment page in AWS Marketplace (**Continue to Launch**) shows
these same steps with your account ID and the image URI already filled in, and
you can copy them from there. They are reproduced here with shell variables.
You can also deploy from the Amazon Bedrock AgentCore console instead of the CLI.

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# From your fulfillment page:
export IMAGE_URI="709825985650.dkr.ecr.us-east-1.amazonaws.com/info-inlet/data-guard-mcp:<version>"
```

### 3.1 Create an IAM role

AgentCore assumes this role to pull the image and write logs. The trust policy
lets AgentCore in your account assume it:

```bash
cat > trustpolicy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AssumeRolePolicy",
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

aws iam create-role \
  --role-name bedrock-agentcore-role \
  --assume-role-policy-document "file://trustpolicy.json"
```

### 3.2 Attach the permissions policy

This is the policy AWS shows on the fulfillment page, less one statement:
AWS's template also allows invoking Bedrock foundation models, and Data Guard
never calls a model, so it is left out.

```bash
cat > permissionspolicy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "ECRImageAccess", "Effect": "Allow",
      "Action": ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"],
      "Resource": ["arn:aws:ecr:${AWS_REGION}:709825985650:repository/*"] },
    { "Sid": "ECRTokenAccess", "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"], "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["logs:DescribeLogStreams", "logs:CreateLogGroup"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/bedrock-agentcore/runtimes/*"] },
    { "Effect": "Allow",
      "Action": ["logs:DescribeLogGroups"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:*"] },
    { "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"] },
    { "Effect": "Allow",
      "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords",
                 "xray:GetSamplingRules", "xray:GetSamplingTargets"],
      "Resource": ["*"] },
    { "Effect": "Allow", "Action": "cloudwatch:PutMetricData", "Resource": "*",
      "Condition": { "StringEquals": { "cloudwatch:namespace": "bedrock-agentcore" } } },
    { "Sid": "GetAgentAccessToken", "Effect": "Allow",
      "Action": ["bedrock-agentcore:GetWorkloadAccessToken",
                 "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
                 "bedrock-agentcore:GetWorkloadAccessTokenForUserId"],
      "Resource": [
        "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:workload-identity-directory/default",
        "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:workload-identity-directory/default/workload-identity/*"] }
  ]
}
JSON

aws iam put-role-policy \
  --role-name bedrock-agentcore-role \
  --policy-name bedrock-agentcore-permissions \
  --policy-document "file://permissionspolicy.json"

export ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/bedrock-agentcore-role"
```

### 3.3 Create the agent runtime

```bash
aws bedrock-agentcore-control create-agent-runtime \
  --region "$AWS_REGION" \
  --agent-runtime-name "data_guard_mcp" \
  --agent-runtime-artifact "{\"containerConfiguration\": {\"containerUri\": \"$IMAGE_URI\"}}" \
  --role-arn "$ROLE_ARN" \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --protocol-configuration '{"serverProtocol": "MCP"}' \
  --environment-variables '{"DG_MAX_INPUT_BYTES": "16777216", "DG_SCRATCH_DIR": "/tmp/data-guard"}'
```

The environment variables are optional; the values above are the defaults.
To use the `hash` or `encrypt` strategies, or the `gdpr_basic` policy pack, add `DG_TOKEN_KEY`; to keep an audit line per call, add `DG_AUDIT_LOG` - see section 7. Note the returned `agentRuntimeArn` and `agentRuntimeId`.

### 3.4 Wait until READY

```bash
aws bedrock-agentcore-control get-agent-runtime \
  --region "$AWS_REGION" --agent-runtime-id <agentRuntimeId> \
  --query status --output text
```

### 3.5 Test it with the AWS CLI

List the tools, using the runtime ARN from 3.3:

```bash
export PAYLOAD='{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {"_meta": {"progressToken": 1}}}'

aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "<agentRuntimeArn>" \
  --content-type "application/json" \
  --accept "application/json, text/event-stream" \
  --payload "$(echo -n "$PAYLOAD" | base64)" output.json
```

`output.json` lists the five tools. You can also invoke the runtime from the
Amazon Bedrock AgentCore console.

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
HTTP (streamable) transport, with SigV4 signing. The five tools then appear
automatically through `tools/list`.

A good default instruction for the calling agent: call `scan_data` first to see
what is present, then `redact_data` with the policy pack that matches your
regime.

---

## 5. Tools reference

Provide input data with **exactly one** of these arguments on any tool that
reads data:

- `text` - inline text (plain text, JSON, NDJSON, YAML, CSV)
- `base64_data` - inline base64-encoded source
- `path` - a file path on the container filesystem, or an `s3://` URI (see the
  note on the `s3://` route in section 8)

Results return inline when small (under 256 KiB). Larger redaction results are
written to a scratch file and the path comes back in the `path` field instead;
`delivery` says which happened. Restored plaintext is the one result that is
never written to disk.

Every data-touching tool accepts `kind` (`auto`, `text`, `json`, `ndjson`,
`yaml`, `csv`) and `min_confidence` (0.0 to 1.0, overriding the policy's own
threshold).

### 5.1 list_detectors

Discovery. Cheap - no data required.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `category` | string | all | filter to `pii`, `phi`, `financial`, or `secret` |

Returns: `detectors` (one entry per entity type, with `detection`,
`requires_context`, `description`, and `countries`), `detector_count`,
`categories`, `policies`, `strategies`, `document_kinds`, and `notes`.

### 5.2 scan_data

Find sensitive values without changing anything.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `kind` | string | `auto` | document kind |
| `policy` | string | `default` | policy pack - decides which entities count |
| `entity_types` | string[] | all | restrict the scan to these entity types |
| `min_confidence` | number | policy's | override the confidence threshold |
| `max_findings` | integer | `200` | cap on findings returned (1-5000) |

Returns: `request_id`, `document_kind`, `policy`, `min_confidence`, `bytes`,
`origin`, `segments_scanned`, `summary` (`total`, `by_entity_type`,
`by_category`, `risk`), `findings`, `findings_truncated`, `document_truncated`.

Each finding carries `entity_type`, `category`, `path` (the JSONPath of the
field inside a structured document, such as `$.customer.email`, and `null` for
plain text), `start`, `end`, `length`, `confidence`, `detector`, and `preview`. `detector` is the provenance string - `luhn+ctx:card` means the shape
passed a Luhn check and the word "card" was nearby. `preview` is masked, and is
the only view of a matched value that ever leaves the server.

### 5.3 redact_data

Detect and rewrite. Structured documents are redacted value-by-value, so the
result still parses as valid JSON, NDJSON, YAML, or CSV.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `kind` | string | `auto` | document kind |
| `policy` | string | `default` | policy pack |
| `strategy` | string | policy's | override the strategy for every entity |
| `key` | string | `DG_TOKEN_KEY` | secret for `hash` and `encrypt` |
| `entity_types` | string[] | all | restrict to these entity types |
| `min_confidence` | number | policy's | override the confidence threshold |
| `extra_spans` | object[] | - | spans you identified yourself (inline input only) |

Returns: `request_id`, `document_kind`, `policy`, `strategy_override`,
`delivery` (`inline_text` or `path`), `bytes`, `text` or `path`, `receipt`,
`reversible`, and the policy pack's `notes`.

`extra_spans` entries are objects with `start`, `end`, `entity_type`, and
optionally `path` and `confidence`. Use it when your agent can see the input and
spots something the server's rules cannot reach - a person's name in bare prose,
for example. Caller spans go through the same overlap resolution as detected
spans, and the receipt counts them separately under `caller`.

The receipt is counts-only and safe to log:

```json
{
  "policy": "default",
  "input_sha256": "dc7ee7b74b9361e04fea2f4b6953adcb6e19aec3eb091dc3a940c42ab6c80cd1",
  "input_bytes": 87,
  "document_kind": "text",
  "total_redactions": 4,
  "by_entity_type": {"AWS_ACCESS_KEY_ID": 1, "CREDIT_CARD": 1, "PERSON": 1, "US_SSN": 1},
  "by_category": {"financial": 1, "pii": 2, "secret": 1},
  "by_strategy": {"label": 4},
  "by_source": {"detected": 4, "model": 0, "caller": 0},
  "min_confidence": 0.5,
  "truncated": false
}
```

`by_source` splits redactions by the evidence behind them: the server's own
deterministic rules (`detected`), a registered model recognizer (`model`, always
zero in this image), and caller-supplied spans (`caller`). Those are three
different evidentiary claims, so they are reported separately rather than summed.
`input_sha256` lets someone holding the original document prove it produced this
receipt, without the receipt revealing anything about the document.

### 5.4 restore_data

Reverse a redaction produced with the `encrypt` strategy.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `key` | string | `DG_TOKEN_KEY` | the same secret used at redaction time |

Returns: `request_id`, `restored_count`, `delivery`, `bytes`, `text`.

```json
{"request_id": "acc39efe...", "restored_count": 2, "delivery": "inline_text",
 "bytes": 50, "text": "Contact: s.chen@northstar.example, SSN 123-45-6789"}
```

Only `encrypt` is reversible. `label`, `mask`, `partial`, `hash`, `token`, and
`remove` are one-way by construction, and no key restores them. The restored
result holds real sensitive values, so it is always returned inline and is never
written to a scratch file. A restore is all-or-nothing: if a placeholder fails to
decrypt, the whole call is refused rather than returning a partial document.

### 5.5 check_policy

A gate: pass or fail a document against a compliance pack, changing nothing.
Use it before sending data to a third party, writing it to a log, or storing it.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` / `path` | string | - | provide exactly one |
| `kind` | string | `auto` | document kind |
| `policy` | string | `hipaa_safe_harbor` | pack to check against |
| `min_confidence` | number | policy's | override the confidence threshold |

Returns: `request_id`, `policy` (the full pack description, including its own
`notes`), `document_kind`, `passed`, `violation_count`, `violations`, `summary`,
`document_truncated`. Each violation carries the entity type, category, count,
maximum confidence, and up to 20 locations - locations only, never values.

When the policy is `hipaa_safe_harbor`, the result also includes
`hipaa_identifiers`: the 18 identifiers from 45 CFR 164.514(b)(2) mapped to what
this server detects, with the three gaps stated explicitly rather than omitted.

### 5.6 Policy packs

| Pack | Covers | Default strategy | Threshold |
|---|---|---|---|
| `default` | everything detectable | `label`, and `remove` for private keys | 0.50 |
| `hipaa_safe_harbor` | the 18 HIPAA Safe Harbor identifiers, 15 of which are covered | `label` | 0.40 |
| `pci_dss` | cardholder data | `mask`; CVV and PIN `remove`; expiry and name `label` | 0.50 |
| `gdpr_basic` | personal and financial data, pseudonymized | `hash` (requires a key) | 0.50 |
| `secrets_only` | credentials and API keys only | `label`, and `remove` for private keys | 0.50 |
| `strict_all` | every category, lowered bar, over-redacts by design | `remove` | 0.35 |

Three packs carry caveats in `notes`, which every tool returns; the other three
return an empty list. Read them: `gdpr_basic` notes that pseudonymized data is
still personal data under GDPR, `hipaa_safe_harbor` names the three identifiers
it does not cover, and `strict_all` states that its lowered threshold admits
false positives on purpose.

`pci_dss` shows why a pack is more than a list of entity types. The PAN is masked
to its last four digits, which the standard permits for display; the CVV and PIN
are removed, because neither may be retained after authorization; the expiry is
labelled rather than masked, because masking keeps a four-character tail and
"11/29" is five characters - masking would leave the value intact while the
receipt reported it redacted.

### 5.7 Redaction strategies

| Strategy | What it leaves behind | Key |
|---|---|---|
| `label` | a readable `<ENTITY_TYPE>` marker | - |
| `mask` | asterisks, keeping the format and a four-character tail | - |
| `partial` | a type-specific fragment: an email domain, an IP subnet, the last four digits | - |
| `hash` | a deterministic keyed token; equal values stay equal, so joins survive | required |
| `token` | sequential `<ENTITY_1>`, `<ENTITY_2>` markers, stable within one document | - |
| `encrypt` | AES-GCM ciphertext, reversible by `restore_data` | required |
| `remove` | nothing - the value is deleted | - |

`hash` and `encrypt` refuse to run without a key rather than producing output
that looks redacted but is not: an unkeyed hash of a nine-digit identifier falls
to a rainbow table in seconds. The key is stretched with HKDF-SHA256, so a
passphrase of any length works, and it is never stored - not in the image, not
in the receipt, not in the audit log.

---

## 6. Examples

These use the `tool` helper from section 4.3. Responses are abridged to the
fields each example is about; all sample data is synthetic.

### 6.1 Scan, then redact

`scan_data` changes nothing - it answers "what is in here, and where", so an
agent can pick a policy or refuse to proceed.

```python
DOC = "Patient Sarah Chen, SSN 123-45-6789, card 4532 0151 1283 0366, key AKIAIOSFODNN7EXAMPLE"

tool("scan_data", text=DOC)
# -> {"summary": {"total": 4,
#                 "by_category": {"financial": 1, "pii": 2, "secret": 1},
#                 "risk": "critical"},
#     "findings": [{"entity_type": "US_SSN", "category": "pii", "path": null,
#                   "start": 24, "end": 35, "length": 11, "confidence": 1.0,
#                   "detector": "us_ssn+ctx:ssn", "preview": "***-**-6789"}, ...]}

tool("redact_data", text=DOC)
# -> {"text": "Patient <PERSON>, SSN <US_SSN>, card <CREDIT_CARD>, key <AWS_ACCESS_KEY_ID>",
#     "receipt": {"total_redactions": 4, "by_strategy": {"label": 4},
#                 "by_source": {"detected": 4, "model": 0, "caller": 0}}}
```

`detector` is provenance: `luhn+ctx:card` means the digits passed a Luhn check
**and** the word "card" was nearby.

### 6.2 Structured documents stay parseable

JSON, NDJSON, YAML, and CSV are redacted value-by-value, so the result still
parses and each finding carries the field `path` it came from.

```python
CSV = "name,ssn,email\nSarah Chen,123-45-6789,s.chen@northstar.example\n"

tool("redact_data", text=CSV, policy="hipaa_safe_harbor")
# -> {"document_kind": "csv",
#     "text": "name,ssn,email\n<PERSON>,<US_SSN>,<EMAIL_ADDRESS>\n"}
```

If parsing fails the server falls back to plain-text scanning rather than
erroring - which still catches anything with a recognizable shape, but loses
whatever was known only by its field name:

```python
tool("scan_data", text='{"account_number": "8829301145"}', kind="json")
# -> {"document_kind": "json",  findings: ["BANK_ACCOUNT_NUMBER"]}

tool("scan_data", text='{"account_number": "8829301145", "note": ', kind="json")
# -> {"document_kind": "text",  findings: []}      <- truncated, fell back
```

So check the returned `document_kind` whenever the document matters.

### 6.3 Gate against a compliance pack

`check_policy` is a pass/fail gate that changes nothing. Put it in front of a
third-party call, a log write, or an export.

```python
NOTE = "Discharge summary for Marcus Delacroix, MRN 4820193, DOB 1974-03-12."

res = tool("check_policy", text=NOTE, policy="hipaa_safe_harbor")
# -> {"passed": false, "violation_count": 2,
#     "violations": [{"entity_type": "MEDICAL_RECORD_NUMBER", "category": "phi",
#                     "count": 1, "max_confidence": 0.85,
#                     "locations": [{"path": null, "start": 44}]},
#                    {"entity_type": "DATE_OF_BIRTH", "category": "pii",
#                     "count": 1, "max_confidence": 0.85,
#                     "locations": [{"path": null, "start": 57}]}]}

if not res["passed"]:
    NOTE = tool("redact_data", text=NOTE, policy="hipaa_safe_harbor")["text"]
```

Violations carry locations, never values. Note what is *not* in that list:
"Marcus Delacroix" has no title or field name in front of it, so it is not
detected - see 6.6. Under `hipaa_safe_harbor` the response also carries
`hipaa_identifiers`, mapping all 18 identifiers to what this server covers.

### 6.4 Reversible redaction

`encrypt` is the only reversible strategy - use it when a downstream system must
process a document it is not allowed to read.

```python
KEY = "a-passphrase-from-your-secret-manager"

red = tool("redact_data", text="SSN 123-45-6789", strategy="encrypt", key=KEY)
# -> {"reversible": true, "text": "SSN <US_SSN:enc:DobsuzwsOYyIKi3yJ_Lc7NBl...>"}

tool("restore_data", text=red["text"], key=KEY)
# -> {"restored_count": 1, "text": "SSN 123-45-6789"}
```

Restores are all-or-nothing, and restored output is always inline - it holds
real values, so it is never written to disk.

### 6.5 Pseudonymize so joins survive

`hash` gives a deterministic keyed token: the same value yields the same token
under the same key, so two datasets still join on the redacted column while
neither reveals the value. This is what `gdpr_basic` uses.

```python
orders  = "customer_email,total
s.chen@northstar.example,412.00
"
support = "customer_email,tickets
s.chen@northstar.example,3
"

tool("redact_data", text=orders,  policy="gdpr_basic", key=KEY)
# -> {"text": "customer_email,total\n<EMAIL_ADDRESS:79f07ff29115>,412.00\n"}

tool("redact_data", text=support, policy="gdpr_basic", key=KEY)
# -> {"text": "customer_email,tickets\n<EMAIL_ADDRESS:79f07ff29115>,3\n"}
```

Same key, same token, so the join holds. A different key gives a different
token, which is how you scope re-linkability per tenant or retention period.

### 6.6 Supply spans the rules cannot reach

A name in bare prose with no title, label, or field name is not detected.
Where your agent can see the text, hand the span over:

```python
tool("redact_data", text="Then Delacroix mentioned the invoice.",
     extra_spans=[{"start": 5, "end": 14, "entity_type": "PERSON", "confidence": 0.9}])
# -> {"text": "Then <PERSON> mentioned the invoice.",
#     "receipt": {"by_source": {"detected": 0, "model": 0, "caller": 1}}}
```

`by_source` keeps the two apart on purpose: `detected` is a rule an auditor can
re-check, `caller` is your claim. A malformed span is refused, not clamped.
`extra_spans` works with inline input only.

### 6.7 Redact a file, keep the receipt

Redacted output over 256 KiB is written to the scratch directory and only the
path comes back, so nothing large floods the model context.

```python
res = tool("redact_data", path="/tmp/exports/customers.ndjson",
           kind="ndjson", policy="default")
# -> {"delivery": "path", "bytes": 318889,
#     "path": "/tmp/data-guard/redacted.ndjson",
#     "receipt": {"input_bytes": 381780, "input_sha256": "e2d59e8e...",
#                 "total_redactions": 12000,
#                 "by_entity_type": {"EMAIL_ADDRESS": 4000, "PERSON": 4000,
#                                    "US_SSN": 4000}}}

audit.write(res["receipt"])   # counts only - safe to log
```

The threshold applies to the *result*, not the input: a large document whose
values collapse to short labels often comes back inline anyway. Read `delivery`
rather than assuming, and take the text from `text` or `path` accordingly.

### 6.8 Tune what counts as a finding

```python
LOG = "user=s.chen@northstar.example ip=10.2.14.9 key=AKIAIOSFODNN7EXAMPLE"

# Only these entity types
tool("redact_data", text=LOG, entity_types=["AWS_ACCESS_KEY_ID"])
# -> "user=s.chen@northstar.example ip=10.2.14.9 key=<AWS_ACCESS_KEY_ID>"

# Raise or lower the bar
tool("scan_data", text=DOC, min_confidence=0.9)

# Keep the shape of the data for debugging
tool("redact_data", text=LOG, strategy="partial")
# -> "user=s*****@northstar.example ip=10.2.*.* key=****************MPLE"

# Over-redact on purpose
tool("redact_data", text=LOG, policy="strict_all")
# -> "user= ip= key="
```

---

## 7. Configuration

All settings are optional - the container ships with working defaults. Override
them as environment variables in the delivery option or runtime configuration.

| Variable | Default | Purpose |
|---|---|---|
| `DG_TOKEN_KEY` | unset | Default key for the `hash` and `encrypt` strategies, and therefore for the `gdpr_basic` pack. Set it if you would rather callers did not pass `key` on every call. Store it in a secret manager, separate from redacted output - anyone holding it can re-link `hash` tokens and decrypt `encrypt` placeholders. |
| `DG_AUDIT_LOG` | off | Where to write one JSON line per data-touching call. `stderr` or `1` sends it to the container's stderr, which is CloudWatch under AgentCore; `stdout` likewise; any other value is treated as a file path. Records carry counts, hashes, rule names, and configuration only - never any part of the document. |
| `DG_MAX_INPUT_BYTES` | `16777216` (16 MiB) | Reject inputs larger than this, checked before reading. The limit is about CPU rather than memory: detection cost is roughly bytes multiplied by the number of rules. |
| `DG_SCRATCH_DIR` | `/tmp/data-guard` (pre-set in the image) | Where redaction results over 256 KiB are written. Already configured and writable; normally leave it as-is. |
| `DG_LOG_REFUSALS` | off | Set to `1` to log one line per deliberately refused request. Useful when a caller reports a failing call and you want to confirm it arrived. |
| `PORT` | `8000` | Listen port. AgentCore expects 8000; changing it is not supported. |

`DG_ALLOW_RAW_PREVIEW` exists for local debugging of detection rules, and it
turns off the guarantee that the server never echoes a matched value. **Do not
set it on a deployed runtime.**

### 7.1 Audit log

If you set `DG_AUDIT_LOG`, a write failure fails the call rather than being
swallowed - from the moment you opt in, the record is part of what a successful
call means. Each record looks like this:

```json
{"ts":"2026-08-25T09:57:56.030Z","request_id":"677914e5612a4e08a530b746497306f4",
 "tool":"redact_data","policy":"default","document_kind":"text","min_confidence":0.5,
 "input_sha256":"6551cbf3...","input_bytes":15,"origin":"inline_text",
 "total_redactions":1,"by_entity_type":{"US_SSN":1},"by_category":{"pii":1},
 "by_strategy":{"label":1},"by_source":{"detected":1,"model":0,"caller":0},
 "delivery":"inline_text","reversible":false}
```

There are deliberately no per-finding rows. `request_id` also comes back in the
tool response, so a response and its audit record can be tied together months
later.

### 7.2 Health check

`GET /healthz` is a real self-test, not a liveness ping. It redacts a synthetic
record and asserts the sensitive values are gone, because for this product the
dangerous failure is not "the process is down" but "the process is up and
quietly not redacting", which a plain 200 would hide.

```json
{"status": "ok", "detected": ["AWS_ACCESS_KEY_ID", "PERSON", "US_SSN"], "leaked_count": 0}
```

Any other `status`, or a 503, means the detection engine is not doing its job.
Treat it as an outage even though the process is running.

---

## 8. Limits and behavior

- Maximum input size defaults to 16 MiB (`DG_MAX_INPUT_BYTES`). Oversized inputs
  are rejected before being read, with a clear error.
- Redaction results over 256 KiB spill to a scratch file, and only the path is
  returned, so nothing large floods the model context. Restored plaintext never
  spills - it is inline or nothing.
- The server is stateless: every request is independent, no key or counter
  survives a call, and AgentCore may route consecutive calls to different
  instances.
- **Unparseable structured input falls back to plain-text scanning** rather than
  raising, because no redaction at all would be the worse outcome. The fallback
  has a cost: plain text carries no field names, so a value with a recognizable
  shape (an SSN, a card number) is still caught, while a value known only by its
  key - a bank account number, an employee ID, a name in a column - is lost. If a
  document matters, pass `kind` explicitly and check that the returned
  `document_kind` is what you expected.
- **Person names in bare prose, with no title, label, role cue, or field name,
  are not detected.** "Dr. Chen", "Patient Marcus Delacroix", and a `name` column
  are found; "...then Delacroix mentioned it" is not. Where your agent can see
  the text, supply those spans through `extra_spans` on `redact_data`; the
  receipt records them under `caller` rather than `detected`.
- Very large or deeply nested documents stop after 200,000 leaf values and set
  `document_truncated` in the response. Treat that flag as "this document was
  only partly examined".
- The `s3://` route on `path` needs the optional `s3` extra, which this image
  does not install, plus an IAM role with read access to the bucket. In a
  standard AgentCore deployment, fetch the object yourself and pass it as `text`
  or `base64_data`.

### 8.1 What this product does and does not claim

This server supports de-identification under the HIPAA Safe Harbor method and
covers 15 of the 18 identifiers; the other three - web URLs, biometric
identifiers, and full-face photographs - are listed in the `hipaa_safe_harbor`
pack's own notes and returned by `check_policy`. It is one control among many,
so it does not by itself make a program "HIPAA compliant". Likewise,
`gdpr_basic` pseudonymizes personal data under Article 4(5), which reduces risk
but does not take the data out of GDPR scope. And no detector finds all PII -
the name limitation above is the documented example.

---

## 9. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Runtime never reaches READY | Check the execution role can pull the image and write logs; review CloudWatch logs under `/aws/bedrock-agentcore/`. |
| 403 / signature errors when calling | Ensure SigV4 signing uses service `bedrock-agentcore` and your IAM principal is allowed to invoke the runtime. |
| `/healthz` returns `degraded` or 503 | The self-test found the engine not redacting. Do not route traffic to the instance; check the logs and redeploy. |
| "Input too large" | Input exceeds `DG_MAX_INPUT_BYTES`; raise it or split the input. |
| "Provide exactly one of text / base64_data / path" | Supply a single input argument. |
| "The 'hash' strategy requires a key" | Pass `key` on the call or set `DG_TOKEN_KEY`. This is a deliberate refusal, not a fault - see section 5.7. |
| "No encrypted placeholders were found" | `restore_data` only reverses `encrypt` output, which looks like `<US_SSN:enc:...>`. Nothing restores `label`, `mask`, `partial`, `hash`, `token`, or `remove`. |
| Restore fails | The key differs from the one used at redaction time. Restores are all-or-nothing, so nothing partial comes back. |
| Fewer findings than expected in a JSON or CSV file | The document may have failed to parse and been scanned as plain text. Check `document_kind` in the response and pass `kind` explicitly. |
| A person's name was not redacted | Expected when the name has no surrounding cue. Supply it through `extra_spans`. |
| More findings than expected | Narrow the scan with `entity_types`, or raise `min_confidence`. `strict_all` over-redacts by design. |

---

## 10. Support

For help with this product, contact the seller through the **Support** link on
the product's AWS Marketplace listing page.
