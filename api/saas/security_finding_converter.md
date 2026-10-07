# Security Finding Converter API (SaaS) - Usage Guide

This guide explains how to subscribe to and use the **Security Finding Converter
API**, a hosted HTTPS API sold as a SaaS subscription in AWS Marketplace. It
converts security findings between the **AWS Security Finding Format (ASFF)**
used by AWS Security Hub and the **Open Cybersecurity Schema Framework (OCSF)**
used by Amazon Security Lake, the new AWS Security Hub and most modern SIEMs.
There is nothing to deploy: subscribe, get an API key, and call the API.

- Base URL: `https://api.llmlinq.com/finding-converter/v1`
- Authentication: API key, `Authorization: Bearer llq_live_...`
- Endpoints: `POST /asff-to-ocsf`, `POST /ocsf-to-asff`, `POST /validate`, `GET /mappings`
- OCSF versions: reads 1.0 to 1.9, writes 1.1 to 1.9
- Input: single findings, arrays, NDJSON, `{"Findings": [...]}` bodies and EventBridge Security Hub events

> Want the same converter running inside your own AWS account, so findings never
> leave it? That is the container product, **Security Finding Converter (MCP
> Server)** - see
> [`mcp/container/security_finding_converter.md`](../../mcp/container/security_finding_converter.md).
> Both products run the same conversion engine and return the same results.

---

## 1. What this product does

Security findings move between tools in two shapes. Security Hub CSPM and every
integration built for it speak ASFF; Security Lake, the new OCSF-based Security
Hub and most SIEM and XDR products speak OCSF. This API translates between them,
in both directions, so a pipeline or an agent can:

- Send Security Hub, GuardDuty, Inspector and Macie findings to an OCSF SIEM or data lake
- Bring findings from any OCSF tool into Security Hub, ready for `BatchImportFindings`
- Move automation from ASFF to the OCSF-based Security Hub
- Check a finding against either format before sending it anywhere

Two properties hold on every call:

- **Nothing is lost silently.** ASFF and OCSF do not line up field for field.
  A value with no exact equivalent is kept, not dropped, and every finding comes
  back with a report that says what happened, why, and whether you need to act.
- **The round trip is exact.** A finding converted from ASFF to OCSF and back
  returns identical to the original. A finding converted from OCSF to ASFF and
  back keeps every original value, within the limits ASFF itself imposes
  (section 8), and the report names anything those limits forced out.

### 1.1 Where values with no equivalent go

| direction | where they are kept |
|---|---|
| ASFF to OCSF | OCSF's own `unmapped` object, under `unmapped.asff` |
| OCSF to ASFF | ASFF's `ProductFields`, one entry per value, named after where it came from (`ocsf/finding_info/title`) |

Converting back puts each value where it was. The report lists each one under
`preserved` with a sentence saying why. A field that does not map one-to-one is
a known difference between two formats, handled, and needs no action.

### 1.2 Which OCSF version you get

The API carries the official OCSF schema of every release. Reading OCSF, the
version comes from each finding's `metadata.version`. Writing OCSF, you choose
with `ocsf_version`:

| `ocsf_version` | writes | use it for |
|---|---|---|
| `auto` (default) | the release the finding came from, else `1.1.0` | round trips |
| `security_hub` | `1.6.0` | the new AWS Security Hub |
| `security_lake` | `1.1.0` | Amazon Security Lake (its AWS sources are 1.1.0; custom sources accept up to 1.3) |
| `latest` | `1.9.0` | the newest OCSF release |
| `1.1.0` to `1.9.0` | that release | a consumer that requires one |

Only fields the chosen release defines, and has not retired, are written.

---

## 2. Prerequisites

- An AWS account and an active subscription to **Security Finding Converter API
  - ASFF and OCSF** in AWS Marketplace.
- An HTTPS client: `curl`, Python, or any language with an HTTP library. No SDK
  is needed.

---

## 3. Subscribe and get your API key

1. On the product's AWS Marketplace page, choose **View purchase options**, pick
   a contract term, and subscribe.
2. Choose **Set up your account**. AWS sends you to
   `https://cloud.llmlinq.com/aws/finding-converter/register`.
3. **Sign in**, or **Create an account**. Any email address works, including a
   work address. The screen names the account the subscription will be attached
   to - check it, then confirm. An AWS account cannot be moved to a different
   account afterwards.
4. Wait for activation. The page shows the subscription as pending until AWS
   confirms it. Leave the page open; it finishes on its own.
5. **Copy the API key.** It starts with `llq_live_` and is shown **once**. Store
   it in a secret manager.

Your key, subscription state and usage stay available at
`https://cloud.llmlinq.com/aws/finding-converter/configure`.

**Lost the key?** Rotate it on the same page. The old key stops working
immediately. Only a hash of the key is stored, so it is replaced, never
recovered.

### 3.1 Free trial

Once offered on the listing, choose **Try for free** instead of a contract term,
then follow steps 2 to 5 above.

- **No charge.** Neither the contract fee nor usage is billed during the trial.
- **Allowance:** 10,000 findings converted. The configure page shows how many
  are used. Past it, conversions return `403 trial_limit_reached`. A request
  that would cross the allowance is refused whole, not cut short, and the
  message says how many findings you may still send. `/validate` and
  `/mappings` keep working.
- **Length:** 30 days. One trial per AWS account.
- **It does not convert on its own.** When it ends, calls return
  `403 subscription_inactive`. To continue, subscribe from the listing page and
  choose **Set up your account** again, attaching it to the same account. Your
  API key stays the same.

---

## 4. Call the API

### 4.1 Authentication

Send the key in either header:

```
Authorization: Bearer llq_live_...
X-Api-Key: llq_live_...
```

`Authorization: llq_live_...` with no `Bearer` prefix is also accepted.

### 4.2 First call

Put your findings in a file as `{"findings": [...]}`. A Security Hub
`GetFindings` response or an EventBridge event works as it is.

```bash
export SFC_API_KEY="llq_live_..."

curl -X POST https://api.llmlinq.com/finding-converter/v1/asff-to-ocsf \
  -H "Authorization: Bearer $SFC_API_KEY" \
  -H "Content-Type: application/json" \
  -d @request.json
```

```json
{
  "source_format": "asff",
  "target_format": "ocsf",
  "ocsf_version_requested": "auto",
  "ocsf_versions_written": ["1.1.0"],
  "envelope": "array",
  "summary": {"received": 1, "converted": 1, "failed": 0, "lossless": true,
              "with_dropped_fields": 0,
              "text": "1 of 1 finding(s) converted. Nothing was lost. ..."},
  "delivery": "inline",
  "findings": [{"class_uid": 2004, "class_name": "Detection Finding", "...": "..."}],
  "reports": [{"index": 0, "outcome": "lossless", "summary": "...", "...": "..."}]
}
```

### 4.3 Client setup (Python)

Standard library only. Every example in section 6 uses this `call` helper.

```python
import json, os, urllib.error, urllib.request

BASE = "https://api.llmlinq.com/finding-converter/v1"
API_KEY = os.environ["SFC_API_KEY"]

def call(endpoint, **body):
    """POST a JSON body to an endpoint and return the parsed response."""
    req = urllib.request.Request(
        f"{BASE}/{endpoint}",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {API_KEY}",
                 "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as err:
        # Error bodies are {"error": "<code>", "message": "..."} - see section 7
        raise RuntimeError(f"{err.code} {err.read().decode()}") from None

def mappings():
    req = urllib.request.Request(f"{BASE}/mappings",
                                 headers={"Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())
```

### 4.4 OpenAPI and interactive reference

These need no key, so you can read them before subscribing:

| | |
|---|---|
| Interactive reference | https://api.llmlinq.com/finding-converter/v1/docs |
| OpenAPI 3 | https://api.llmlinq.com/finding-converter/v1/openapi.yaml |

`openapi.yaml` works with Postman, Insomnia, Bruno, or `openapi-generator` for a
typed client.

---

## 5. Endpoint reference

Every `POST` takes findings in **exactly one** of these fields:

- `findings` - JSON: one finding, an array, a `{"Findings": [...]}` body
  (BatchImportFindings, GetFindings, GetFindingsV2), or an EventBridge Security
  Hub event (`{"detail": {"findings": [...]}}`)
- `text` - the same as a string, including NDJSON (one finding per line)
- `base64_data` - the same, base64-encoded

A request accepts up to 10,000 findings. Converted findings always come back
inline, up to 256 KiB; send fewer findings per request beyond that.

Both conversion endpoints take `on_error`: `fail` (default) refuses the whole
request on the first invalid finding, named by its index, so a batch is never
half converted without you knowing; `skip` converts the rest and lists each
failure under `errors`.

### 5.1 POST /asff-to-ocsf

| Field | Type | Default | Notes |
|---|---|---|---|
| `findings` / `text` / `base64_data` | - | - | provide exactly one |
| `target_class` | string | `auto` | `auto`, `detection` (2004), `vulnerability` (2002) or `compliance` (2003) |
| `ocsf_version` | string | `auto` | see section 1.2 |
| `include_unmapped` | boolean | `true` | keep ASFF fields with no OCSF equivalent in `unmapped.asff`. Turn off only if your consumer rejects `unmapped`; those fields are then dropped and reported |
| `on_error` | string | `fail` | `fail` or `skip` |

With `target_class` `auto`, a finding with `Vulnerabilities` becomes a
Vulnerability Finding, one with `Compliance` a Compliance Finding, and anything
else a Detection Finding.

Returns `ocsf_version_requested`, `ocsf_versions_written`, `envelope`,
`summary`, `delivery`, `bytes`, `findings`, `reports`, and `errors` when
`on_error` is `skip`.

### 5.2 POST /ocsf-to-asff

OCSF findings (any Findings class, 2001-2007) to ASFF, ready for
`BatchImportFindings`.

| Field | Type | Default | Notes |
|---|---|---|---|
| `findings` / `text` / `base64_data` | - | - | provide exactly one |
| `aws_account_id` | string | from the finding | 12 digits. **Required** when the finding is not about an AWS account (an Azure, GCP or SaaS finding): the account it will be imported into |
| `region` | string | from the finding | the Security Hub region, used to build `ProductArn` when the finding has none |
| `product_arn` | string | built | a Security Hub product ARN to use for every finding |
| `generator_id` | string | from the finding | used only when the finding names no rule or detector |
| `strict` | boolean | `false` | refuse, rather than drop, any value ASFF's limits cannot hold |
| `on_error` | string | `fail` | `fail` or `skip` |

The account is never invented. A finding without one is refused with a message
naming the field to pass.

Returns as 5.1, plus `batch_import`: `BatchImportFindings` takes at most 100
findings per call, and `calls_needed` says how many calls this batch needs.

### 5.3 POST /validate

Check findings of either format without converting them. Not billed.

| Field | Type | Default | Notes |
|---|---|---|---|
| `findings` / `text` / `base64_data` | - | - | provide exactly one |
| `format` | string | `auto` | `auto`, `asff` or `ocsf` |

Returns, per finding, `format`, `ocsf_version` (for OCSF), `valid`, and
`issues`, each with a `path`, a `message` and a `level` (`error` means the
target system would reject it; `warning` means it would accept it but you should
know). Value types are not checked, and a pass is not a guarantee that Security
Hub will accept a finding.

### 5.4 GET /mappings

The field-by-field mapping table, the OCSF versions read and written, the named
targets, the envelopes accepted, the severity, workflow and compliance
crossings, the date of the OCSF schema snapshot, and the round-trip guarantee.
Not billed.

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

These use the `call` helper from section 4.3. Responses are abridged to the
fields each example is about; all sample data is synthetic.

### 6.1 Security Hub findings to OCSF

A GuardDuty finding, written for the new AWS Security Hub:

```python
res = call("asff-to-ocsf", findings=guardduty_finding, ocsf_version="security_hub")

res["findings"][0]
# -> {"class_uid": 2004, "class_name": "Detection Finding",
#     "severity_id": 2, "severity": "Low", "status": "New",
#     "metadata": {"version": "1.6.0", ...},
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
back = call("ocsf-to-asff", findings=res["findings"])
back["findings"][0] == guardduty_finding
# -> True
```

### 6.3 Import a non-AWS OCSF finding into Security Hub

An XDR detection about an Azure VM has no AWS account, so it is refused until
you name the account to import into:

```python
call("ocsf-to-asff", findings=azure_detection)
# -> RuntimeError: 400 {"error": "invalid_request", "message": "Finding 0: This finding
#    names no AWS account (cloud.account.uid on an AWS cloud). Pass aws_account_id:
#    the account the finding will be imported into."}

res = call("ocsf-to-asff", findings=azure_detection,
           aws_account_id="123456789012", region="us-east-1")
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

### 6.4 Convert what EventBridge delivers

An EventBridge rule on `Security Hub Findings - Imported` delivers an event;
pass it as it is:

```python
res = call("asff-to-ocsf", findings=eventbridge_event, ocsf_version="security_lake")
res["envelope"], res["ocsf_versions_written"]
# -> ("eventbridge", ["1.1.0"])
```

### 6.5 Validate before sending

```python
call("validate", findings=[asff_finding, ocsf_finding])
# -> {"summary": {"received": 2, "valid": 2, "invalid": 0},
#     "results": [{"index": 0, "format": "asff", "valid": true, "issues": []},
#                 {"index": 1, "format": "ocsf", "ocsf_version": "1.6.0",
#                  "valid": true, "issues": []}], ...}
```

### 6.6 A large export

Send it in batches. NDJSON works well as `text`, a few hundred findings per
request:

```python
lines = open("findings.ndjson").read().splitlines()
for start in range(0, len(lines), 200):
    res = call("asff-to-ocsf", text="\n".join(lines[start:start + 200]),
               ocsf_version="security_hub", on_error="skip")
    print(res["summary"]["text"])
```

---

## 7. Errors

Errors are JSON: `{"error": "<code>"}`, plus `message` where it helps. Branch on
`error`, not on `message`. Messages never quote your findings.

| Status | `error` | Meaning and fix |
|---|---|---|
| 400 | `invalid_json` | The body is not a JSON object. |
| 400 | `unsupported_parameters` | A field this endpoint does not accept; `parameters` lists them. `path` is never accepted over HTTP. |
| 400 | `invalid_request` | A finding or a field is wrong. `message` says what to change, and names the finding by its index. |
| 401 | `api_key_required` | No key, or a value that is not one of our keys. |
| 401 | `invalid_api_key` | A key we did not issue, or one that has been rotated. |
| 403 | `subscription_inactive` | The key is valid but the subscription is not active (`state` says why). Fixed in AWS Marketplace, not with a new key. |
| 403 | `trial_limit_reached` | A free trial has used its allowance; `limits` states it. Subscribe to continue with the same key (section 3.1). |
| 404 | - | Unknown path or method; the body is `{"message": "Not Found"}`. Check the base URL includes `/finding-converter/v1`. |
| 413 | `result_too_large` | The converted findings exceed 256 KiB. Send fewer findings per request. |
| 429 | - | Throttled. Retry with exponential backoff. |
| 500 | `internal_error` | An unexpected fault. Retry; if it persists, contact support. |

---

## 8. Limits and behavior

| Limit | Value |
|---|---|
| Request body | about 6 MB |
| Response | up to 256 KiB of converted findings, always inline; larger results are `413 result_too_large` |
| Findings per request | 10,000 |
| Rate | 100 requests/second per endpoint across the service, with bursts to 200 |

- **ASFF's own limits** apply to OCSF -> ASFF: `Title` 256 characters,
  `Description` 1,024, `Remediation` text 512, 32 resources, 50 types, 50
  `ProductFields` of 2,048 characters, and 240 KB per finding. Shortened fields
  keep their full original in `ProductFields`; only a value that cannot fit
  there either is dropped, and the report names it. Three `ProductFields` are
  left free for the entries Security Hub adds on import.
- **Not yet mapped to native OCSF fields:** ASFF's `Network`, `Process`,
  `Malware`, `ThreatIntelIndicators` and `Action`. They are kept in
  `unmapped.asff` and come back exactly, but an OCSF consumer does not see them
  as OCSF evidence fields yet.
- **An edited finding keeps its edit.** If a finding converted from ASFF is
  changed in OCSF and converted back, the OCSF values win, and the report names
  each field whose original ASFF value was not restored.
- **Stateless and not retained.** Request bodies are converted in memory and
  never stored or logged. If your findings must never leave your own AWS
  account, use the container product instead.

### 8.1 Billing

The subscription is a contract (monthly or annual) plus usage, billed through
AWS Marketplace. Current prices are on the listing page.

**The contract fee includes 10,000 findings converted every month**, on monthly
and annual contracts alike. Only findings beyond that are billed, per 1,000
findings converted.

- A finding counts when it appears in a successful conversion's `findings`.
  A finding in `errors`, a refused request, `/validate` and `/mappings` are
  never counted.
- The allowance runs per calendar month in UTC and resets at 00:00 UTC on the
  first of each month. Unused allowance does not carry over.
- The configure page shows this month's use of the allowance, when it resets,
  and your total since you subscribed. Billed usage appears in the AWS Billing
  console.
- A contract cannot be cancelled mid-term from the console. Turn off
  auto-renewal to stop further billing, and see the refund policy on the
  listing.
- A free trial is not billed and its usage is not reported to AWS Marketplace.

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
| `401 api_key_required` | No `Authorization` or `X-Api-Key` header, or the value does not start with `llq_live_`. |
| `401 invalid_api_key` | The key was rotated or mistyped. Copy the current key, or rotate it at `cloud.llmlinq.com/aws/finding-converter/configure`. |
| `403 subscription_inactive` | The subscription has ended, or has not finished activating. Check AWS Marketplace and the configure page. |
| `403 trial_limit_reached` | The free trial used its allowance. Subscribe from the listing page and set up your account again; the key stays the same. |
| Setup page shows "We could not confirm that subscription" | Start again from **Set up your account** in the AWS Marketplace console; the setup link is single-use and expires. |
| "This finding names no AWS account" | The OCSF finding is about a non-AWS resource. Pass `aws_account_id`: the account it will be imported into. |
| "ASFF needs a ProductArn ... Pass region" | The finding has no Security Hub product ARN and no AWS region. Pass `region`, or `product_arn`. |
| "this is not an ASFF finding (it looks like OCSF)" | You called the endpoint for the other direction. Use `/ocsf-to-asff`. |
| "ocsf_version must be one of ..." | Use a release from 1.1.0 to 1.9.0, `latest`, `security_hub`, `security_lake` or `auto`. OCSF 1.0 can be read but not written. |
| A report says `lossy` | ASFF's limits could not hold a value; `dropped` names it. Pass `strict: true` to refuse instead. |
| `400 unsupported_parameters` with `path` | File paths are not accepted over HTTP. Send the content as `findings`, `text` or `base64_data`. |
| `413 result_too_large` | Send fewer findings per request. |
| `429` | You are over the rate limit. Retry with exponential backoff. |

---

## 10. Support

Email **contact@infoinlet.com**. We reply within one business day, Monday to
Friday. If a conversion looks wrong, send the report it returned: reports name
fields and reasons and never contain a finding's values. Never include your API
key.
