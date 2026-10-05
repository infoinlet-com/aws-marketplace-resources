# Security Finding Converter (MCP Server) - Usage Guide

This guide explains how to deploy and use **Security Finding Converter**, an MCP
(Model Context Protocol) server delivered as a container and hosted on **Amazon
Bedrock AgentCore Runtime**. It converts security findings between the **AWS
Security Finding Format (ASFF)** used by AWS Security Hub and the **Open
Cybersecurity Schema Framework (OCSF)** used by Amazon Security Lake, the new
AWS Security Hub and most modern SIEMs. You deploy it in your own AWS account,
so your findings never leave your boundary. Nothing phones home, and nothing is
stored between requests.

- Protocol: MCP over streamable HTTP (`POST /mcp`)
- Architecture: ARM64 (AWS Graviton), stateless, listens on port `8000`
- Tools: `convert_asff_to_ocsf`, `convert_ocsf_to_asff`, `validate_finding`, `list_mappings`
- OCSF versions: reads 1.0 to 1.9, writes 1.1 to 1.9
- Input: single findings, arrays, NDJSON, `{"Findings": [...]}` bodies and EventBridge Security Hub events

---

## 1. What this product does

Security findings move between tools in two shapes. Security Hub CSPM and every
integration built for it speak ASFF; Security Lake, the new OCSF-based Security
Hub and most SIEM and XDR products speak OCSF. This server translates between
them, in both directions, so an agent or a pipeline can:

- Send Security Hub, GuardDuty, Inspector and Macie findings to an OCSF SIEM or data lake
- Bring findings from any OCSF tool into Security Hub, ready for `BatchImportFindings`
- Move automation from ASFF to the OCSF-based Security Hub
- Give a security-operations agent one consistent format across tools
- Check a finding against either format before sending it anywhere

Two properties hold on every call:

- **Nothing is lost silently.** ASFF and OCSF do not line up field for field.
  A value with no exact equivalent is kept, not dropped, and every finding comes
  back with a report that says what happened, why, and whether you need to act.
- **The round trip is exact.** A finding converted from ASFF to OCSF and back
  returns identical to the original. A finding converted from OCSF to ASFF and
  back keeps every original value, within the limits ASFF itself imposes
  (section 8), and the report names anything those limits forced out.

### 1.1 Why the formats do not map one-to-one, and why that needs no action

Some fields exist in only one format. ASFF has a 0-100 `Normalized` severity
score beside its severity label; OCSF has the label only. OCSF records ATT&CK
techniques; ASFF has no field for them. Rather than drop such values, the
converter keeps them in the place each format sets aside for exactly this:

| direction | where values with no equivalent are kept |
|---|---|
| ASFF to OCSF | OCSF's own `unmapped` object, under `unmapped.asff` |
| OCSF to ASFF | ASFF's `ProductFields`, one entry per value, named after where it came from (`ocsf/finding_info/title`) |

Converting back puts each value where it was. The report lists each one under
`preserved`, with a sentence saying why, so a field that does not map
one-to-one reads as what it is: a known difference between two formats,
handled.

### 1.2 Which OCSF version you get

The server carries the official OCSF schema of every release, from the OCSF
project's own schema server, and uses it in both directions:

- **Reading OCSF**, the version comes from the finding's `metadata.version`,
  and every shape that release uses is understood - a single `resource` in
  1.1, `labels` or `tags`, `comment` or `notes` in 1.9. A version newer than
  the server knows is read with the newest schema it has; unknown fields are
  kept, and the report says so.
- **Writing OCSF**, you choose the release, or say where the findings are going:

| `ocsf_version` | writes | use it for |
|---|---|---|
| `auto` (default) | the release the finding came from, else `1.1.0` | round trips |
| `security_hub` | `1.6.0` | the new AWS Security Hub |
| `security_lake` | `1.1.0` | Amazon Security Lake (its AWS sources are 1.1.0; custom sources accept up to 1.3) |
| `latest` | `1.9.0` | the newest OCSF release |
| `1.1.0` to `1.9.0` | that release | a consumer that requires one |

Only fields the chosen release defines, and has not retired, are written. New
OCSF releases are added in later versions of this product.

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

You can deploy from the AgentCore console (select this product's container
image) or with the AWS CLI. The CLI flow below is fully reproducible.

Set shared variables:

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# The container image URI is provided on your AWS Marketplace fulfillment page
# after you subscribe. It looks like:
#   <registry>.dkr.ecr.<region>.amazonaws.com/<path>/security-finding-converter-mcp:<version>
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

aws iam create-role --role-name security-finding-converter-mcp-role \
  --assume-role-policy-document file://trust.json --region "$AWS_REGION"
aws iam put-role-policy --role-name security-finding-converter-mcp-role \
  --policy-name exec --policy-document file://perms.json
export ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/security-finding-converter-mcp-role"
```

To let the server read findings from S3 with an `s3://` path (section 5),
add `s3:GetObject` (and `s3:GetObjectVersion` if you use versioning) on that
bucket to `perms.json`. Nothing else needs S3.

### 3.2 Create the agent runtime

```bash
cat > runtime.json <<JSON
{
  "agentRuntimeName": "security_finding_converter_mcp",
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
    result = call("tools/call", {"name": name, "arguments": arguments})["result"]
    if result.get("isError"):
        raise RuntimeError(result["content"][0]["text"])
    return result.get("structuredContent") or json.loads(result["content"][0]["text"])

# Discover tools
print([t["name"] for t in call("tools/list")["result"]["tools"]])
```

The `tool` helper is used by every example in section 6.

### 4.4 Wiring it into an MCP-capable agent

Point your agent or framework's MCP client at the endpoint URL above using its
HTTP (streamable) transport, with SigV4 signing. The four tools then appear
automatically through `tools/list`, with descriptions that tell the model how
to call them.

A good default instruction for the calling agent: read each finding's report
`summary` before acting on the output, and pass `aws_account_id` and `region`
when converting OCSF findings that are not about an AWS account.

---

## 5. Tools reference

Provide findings with **exactly one** of these arguments:

- `findings` - JSON you already hold: one finding, an array, a
  `{"Findings": [...]}` body (BatchImportFindings, GetFindings, GetFindingsV2),
  or an EventBridge Security Hub event (`{"detail": {"findings": [...]}}`)
- `text` - the same as a string, including NDJSON (one finding per line)
- `base64_data` - the same, base64-encoded
- `path` - a file path on the container filesystem, or an `s3://bucket/key`
  object (the execution role needs `s3:GetObject`, section 3.1)

Converted findings return inline when they total under 256 KiB. Larger results
are written to a scratch file and `path` comes back instead of `findings`;
`delivery` says which happened. A call accepts up to 10,000 findings.

Both conversion tools take `on_error`: `fail` (default) refuses the whole call
on the first invalid finding, named by its index, so a batch is never half
converted without you knowing; `skip` converts the rest and lists each failure
under `errors`.

### 5.1 list_mappings

Discovery. Cheap - no findings required. Returns the field-by-field mapping
table, the OCSF versions read and written, the named targets, the envelopes
accepted, the enumeration crossings (severity, workflow status, compliance
status), the date of the OCSF schema snapshot, and the round-trip guarantee.

### 5.2 convert_asff_to_ocsf

ASFF findings to OCSF.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `findings` / `text` / `base64_data` / `path` | - | - | provide exactly one |
| `target_class` | string | `auto` | `auto`, `detection` (2004), `vulnerability` (2002) or `compliance` (2003) |
| `ocsf_version` | string | `auto` | see section 1.2 |
| `include_unmapped` | boolean | `true` | keep ASFF fields with no OCSF equivalent in `unmapped.asff`. Turn off only if your consumer rejects `unmapped`; those fields are then dropped and reported |
| `on_error` | string | `fail` | `fail` or `skip` |

With `target_class` `auto`, a finding with `Vulnerabilities` becomes a
Vulnerability Finding, one with `Compliance` a Compliance Finding, and anything
else a Detection Finding.

Returns: `ocsf_version_requested`, `ocsf_versions_written`, `envelope`,
`summary`, `delivery`, `bytes`, `findings` (or `path`), `reports`, and `errors`
when `on_error` is `skip`.

### 5.3 convert_ocsf_to_asff

OCSF findings (any Findings class, 2001-2007) to ASFF, ready for
`BatchImportFindings`.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `findings` / `text` / `base64_data` / `path` | - | - | provide exactly one |
| `aws_account_id` | string | from the finding | 12 digits. **Required** when the finding is not about an AWS account (an Azure, GCP or SaaS finding): the account it will be imported into |
| `region` | string | from the finding | the Security Hub region, used to build `ProductArn` when the finding has none |
| `product_arn` | string | built | a Security Hub product ARN to use for every finding |
| `generator_id` | string | from the finding | used only when the finding names no rule or detector |
| `strict` | boolean | `false` | refuse, rather than drop, any value ASFF's limits cannot hold |
| `on_error` | string | `fail` | `fail` or `skip` |

The account is never invented. A finding without one is refused with a message
naming the parameter to pass.

Returns: as 5.2, plus `batch_import`: `BatchImportFindings` takes at most 100
findings per call, and `calls_needed` says how many calls this batch needs.

### 5.4 validate_finding

Check findings of either format without converting them.

| Argument | Type | Default | Notes |
|---|---|---|---|
| `findings` / `text` / `base64_data` / `path` | - | - | provide exactly one |
| `format` | string | `auto` | `auto`, `asff` or `ocsf` |

Returns: per finding, `format`, `ocsf_version` (for OCSF), `valid`, and
`issues`, each with a `path`, a `message` and a `level` (`error` means the
target system would reject it; `warning` means it would accept it but you
should know). Checks: required fields, enumerations, ASFF's documented limits,
OCSF `type_uid` arithmetic, and for OCSF every attribute name against the
official schema of the finding's own version. Value types are not checked, and
a pass is not a guarantee Security Hub will accept a finding.

### 5.5 The conversion report

Every converted finding has a report in `reports`, in the same order:

| Field | Meaning |
|---|---|
| `outcome` | `lossless` - nothing lost. `lossless_with_defaults` - nothing lost, and fields the target requires were filled in. `lossy` - see `dropped` |
| `summary` | the report in one sentence, ending "No action needed." when nothing needs your attention |
| `ocsf_version` | the OCSF release written (to OCSF) or read (from OCSF) |
| `preserved` | values with no exact equivalent, each with `kept_in` and `why`. Not a loss |
| `synthesized` | required fields filled in, each with `from` and `why` |
| `truncated` | fields shortened to fit an ASFF limit; the full original is kept |
| `dropped` | values that could not be kept, each with `reason` and `action` |
| `warnings` | anything else worth knowing, in sentences |

| `outcome` | do you need to act? |
|---|---|
| `lossless` | no |
| `lossless_with_defaults` | no; review `synthesized` only if you rely on those fields |
| `lossy` | yes: read `dropped`, or use `strict` to refuse instead |

Reports name fields and reasons and **never contain a finding's values**, so
they are safe to log and to paste into a support request.

---

## 6. Examples

These use the `tool` helper from section 4.3. Responses are abridged to the
fields each example is about; all sample data is synthetic.

### 6.1 Security Hub findings to OCSF

A GuardDuty finding, written for the new AWS Security Hub:

```python
res = tool("convert_asff_to_ocsf", findings=guardduty_finding, ocsf_version="security_hub")

res["findings"][0]
# -> {"class_uid": 2004, "class_name": "Detection Finding",
#     "severity_id": 2, "severity": "Low", "status": "New",
#     "metadata": {"version": "1.6.0",
#                  "product": {"uid": "arn:aws:securityhub:us-east-1::product/aws/guardduty",
#                              "name": "GuardDuty", "vendor_name": "Amazon"}},
#     "resources": [{"uid": "arn:aws:ec2:us-east-1:111122223333:instance/i-0a1b2c3d4e5f60718",
#                    "type": "AwsEc2Instance", "region": "us-east-1",
#                    "tags": [{"name": "Name", "value": "bastion"}, ...]}],
#     "vendor_attributes": {"severity_id": 2, "severity": "Low"},
#     "unmapped": {"asff": {"Network": {...}, "Severity": {...}, ...}}, ...}

res["reports"][0]["summary"]
# -> "Converted with nothing lost. 8 field(s) have no exact equivalent in OCSF and
#     are kept in unmapped.asff, so converting back restores them exactly. No action needed."

res["reports"][0]["preserved"][1]
# -> {"field": "Network", "kept_in": "unmapped.asff.Network",
#     "why": "OCSF expresses this as evidence and observables, which this release does
#             not map yet. The original is kept in unmapped.asff.Network, so converting
#             back to ASFF restores it exactly."}
```

### 6.2 Back to ASFF, identical

```python
back = tool("convert_ocsf_to_asff", findings=res["findings"])
back["findings"][0] == guardduty_finding
# -> True
```

### 6.3 Import a non-AWS OCSF finding into Security Hub

An XDR detection about an Azure VM has no AWS account, so it is refused until
you name the account to import into:

```python
tool("convert_ocsf_to_asff", findings=azure_detection)
# -> error: "Finding 0: This finding names no AWS account (cloud.account.uid on an
#            AWS cloud). Pass aws_account_id: the account the finding will be
#            imported into."

res = tool("convert_ocsf_to_asff", findings=azure_detection,
           aws_account_id="123456789012", region="us-east-1")
res["findings"][0]
# -> {"ProductArn": "arn:aws:securityhub:us-east-1:123456789012:product/123456789012/default",
#     "GeneratorId": "ebe-7", "AwsAccountId": "123456789012",
#     "Types": ["TTPs/Credential Access"], "Severity": {"Label": "CRITICAL"},
#     "Workflow": {"Status": "NOTIFIED"},
#     "ProductFields": {"ocsf/cloud/account/uid": "8f3c2b1a-...", ...}, ...}

res["reports"][0]["outcome"], res["reports"][0]["warnings"]
# -> ("lossless_with_defaults",
#     ["OCSF severity 'Fatal' has no ASFF equivalent (ASFF has Informational, Low,
#       Medium, High and Critical), so the nearest, CRITICAL, was used. The original
#       level is kept in ProductFields."])

res["batch_import"]
# -> {"max_per_call": 100, "calls_needed": 1}
```

Then send it with `aws securityhub batch-import-findings` or
`boto3.client("securityhub").batch_import_findings(Findings=res["findings"])`.
The `ProductArn` built here is the custom-integration form Security Hub accepts
for findings you import into your own account.

### 6.4 Convert what EventBridge delivers

An EventBridge rule on `Security Hub Findings - Imported` delivers an event;
pass it as it is:

```python
res = tool("convert_asff_to_ocsf", findings=eventbridge_event, ocsf_version="security_lake")
res["envelope"], res["ocsf_versions_written"]
# -> ("eventbridge", ["1.1.0"])
```

### 6.5 When ASFF's limits bite

ASFF allows at most 50 `ProductFields` of 2,048 characters. An OCSF value
longer than that cannot be kept, and the report says so:

```python
res = tool("convert_ocsf_to_asff", findings=finding_with_a_huge_field,
           aws_account_id="123456789012", region="us-east-1")
res["reports"][0]["outcome"]
# -> "lossy"
res["reports"][0]["dropped"]
# -> [{"field": "unmapped.blob",
#      "reason": "its value is longer than a ProductFields value may be (2,048)",
#      "action": "Review: this value is not in the output. Pass strict=true to refuse
#                 the conversion instead of dropping."}]

tool("convert_ocsf_to_asff", findings=finding_with_a_huge_field,
     aws_account_id="123456789012", region="us-east-1", strict=True)
# -> error: "Finding 0: strict: these OCSF values cannot be carried in ASFF: unmapped.blob"
```

### 6.6 Validate before sending

```python
tool("validate_finding", findings=[asff_finding, ocsf_finding])
# -> {"summary": {"received": 2, "valid": 2, "invalid": 0},
#     "results": [{"index": 0, "format": "asff", "valid": true, "issues": []},
#                 {"index": 1, "format": "ocsf", "ocsf_version": "1.6.0", "valid": true,
#                  "issues": [{"path": "rogue", "level": "warning",
#                              "message": "not defined in OCSF 1.6.0"}]}]}
```

### 6.7 Convert a large export from S3

```python
res = tool("convert_asff_to_ocsf", path="s3://my-security-exports/2026-10/findings.ndjson",
           ocsf_version="security_hub", on_error="skip")
res["delivery"]
# -> "path" once the converted findings exceed 256 KiB; "inline" below that
res["summary"]["text"]
# -> one sentence: how many converted, how many failed (listed in res["errors"]),
#    and whether anything was lost
```

Large results are written to a file at `res["path"]` in the container's
scratch directory, so a large export never floods the model context.

---

## 7. Configuration

All settings are optional - the container ships with working defaults. Override
them as environment variables in the delivery option or runtime configuration.

| Variable | Default | Purpose |
|---|---|---|
| `SFC_MAX_INPUT_BYTES` | `33554432` (32 MiB) | Reject inputs larger than this, checked before reading. |
| `SFC_SCRATCH_DIR` | `/tmp` (pre-set in the image) | Where converted results over 256 KiB are written. Already configured and writable; normally leave it as-is. |
| `SFC_LOG_REFUSALS` | off | Set to `1` to log one line per deliberately refused request. Useful when a caller reports a failing call and you want to confirm it arrived. |
| `PORT` | `8000` | Listen port. AgentCore expects 8000; changing it is not supported. |

### 7.1 Health check

`GET /healthz` is a real self-test, not a liveness ping. It converts a
synthetic finding from ASFF to OCSF and back and checks it returns identical,
because for this product the dangerous failure is not "the process is down" but
"the process is up and losing fields", which a plain 200 would hide.

```json
{"status": "ok", "roundtrip_exact": true, "version": "0.1.0"}
```

Any other `status`, or a 503, means conversions are not reliable. Treat it as
an outage even though the process is running.

---

## 8. Limits and behavior

- **ASFF's own limits** apply to OCSF -> ASFF: `Title` 256 characters,
  `Description` 1,024, `Remediation` text 512, 32 resources, 50 types, 50
  `ProductFields` of 2,048 characters, and 240 KB per finding. Shortened fields
  keep their full original in `ProductFields`; only a value that cannot fit
  there either is dropped, and the report names it.
- Of the 50 `ProductFields`, three are left free for the `aws/securityhub/*`
  entries Security Hub adds when it imports a finding.
- Maximum input size defaults to 32 MiB (`SFC_MAX_INPUT_BYTES`), and a call
  accepts up to 10,000 findings.
- The server is stateless: every request is independent, and AgentCore may
  route consecutive calls to different instances.
- **Not yet mapped to native OCSF fields:** ASFF's `Network`, `Process`,
  `Malware`, `ThreatIntelIndicators` and `Action`. They are kept in
  `unmapped.asff` and come back exactly, but an OCSF consumer does not see them
  as OCSF evidence fields yet.
- **An edited finding keeps its edit.** If a finding converted from ASFF is
  changed in OCSF (a status updated in your SIEM, say) and converted back, the
  OCSF values win, and the report names each field whose original ASFF value was
  not restored.

### 8.1 How this compares with AWS's own mapping

AWS has published how Security Hub CSPM automation-rule fields map to OCSF
fields in the new Security Hub ("Security Hub CSPM automation rule migration to
Security Hub", AWS Security Blog). This converter puts each of those values
where AWS puts them, with two deliberate differences:

- **GeneratorId**: AWS lists no OCSF equivalent. It is written to
  `finding_info.analytic.uid`, OCSF's field for the rule that produced a finding.
- **Severity**: ASFF keeps two severities, the current one (which people may
  change) and the provider's original (`FindingProviderFields`). The current one
  goes to `severity_id` and the provider's original to `vendor_attributes`, so a
  finding whose severity was changed keeps both.

### 8.2 What this product does and does not claim

ASFF -> OCSF -> ASFF returns the identical finding. OCSF -> ASFF keeps every
value within ASFF's documented limits and reports what those limits force out.
Validation is structural, and checks attribute names against the official OCSF
schema; it is not a full schema validation of value types, and passing it does
not guarantee that Security Hub will accept a finding.

---

## 9. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Runtime never reaches READY | Check the execution role can pull the image and write logs; review CloudWatch logs under `/aws/bedrock-agentcore/`. |
| 403 / signature errors when calling | Ensure SigV4 signing uses service `bedrock-agentcore` and your IAM principal is allowed to invoke the runtime. |
| `/healthz` returns `degraded` or 503 | The self-test found the round trip not exact. Do not route traffic to the instance; check the logs and redeploy. |
| "This finding names no AWS account" | The OCSF finding is about a non-AWS resource. Pass `aws_account_id`: the account it will be imported into. |
| "ASFF needs a ProductArn ... Pass region" | The finding has no Security Hub product ARN and no AWS region. Pass `region`, or `product_arn`. |
| "this is not an ASFF finding (it looks like OCSF)" | You called the tool for the other direction. Use `convert_ocsf_to_asff`. |
| "Not a valid ASFF finding" / "Not a valid OCSF finding" | The message names the field. Run `validate_finding` to see every issue at once. |
| "ocsf_version must be one of ..." | Use a release from 1.1.0 to 1.9.0, `latest`, `security_hub`, `security_lake` or `auto`. OCSF 1.0 can be read but not written. |
| A report says `lossy` | ASFF's limits could not hold a value; `dropped` names it. Pass `strict=true` to refuse instead. |
| Output has `path` instead of `findings` | The result was over 256 KiB and was written to the scratch directory. Send fewer findings per call to get them inline. |
| "Input too large" | Input exceeds `SFC_MAX_INPUT_BYTES`; raise it or split the input. |
| "Provide exactly one of findings / text / base64_data / path" | Supply a single input argument. |
| "Could not read s3://..." | The execution role needs `s3:GetObject` on that bucket (section 3.1). |

---

## 10. Support

For help with this product, contact the seller through the **Support** link on
the product's AWS Marketplace listing page, or email contact@infoinlet.com.
A report from the tool response is the most useful thing to include: it names
fields and reasons and never contains a finding's values, so you can send it
without sending your data.
