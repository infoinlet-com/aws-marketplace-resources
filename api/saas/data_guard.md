# Data Guard API (SaaS) - Usage Guide

This guide explains how to subscribe to and use the **Data Guard API**, a
hosted HTTPS API sold as a SaaS subscription in AWS Marketplace. There is
nothing to deploy: subscribe, get an API key, and call the API.

- Base URL: `https://api.llmlinq.com/data-guard/v1`
- Authentication: API key, `Authorization: Bearer llq_live_...`
- Endpoints: `POST /scan`, `POST /redact`, `POST /restore`, `POST /check`, `GET /detectors`
- Document kinds: text, JSON, NDJSON, YAML, CSV
- Coverage: 64 entity types across PII, PHI, financial data, and secrets
- Also usable as MCP tools through an **Amazon Bedrock AgentCore Gateway** (section 7)

> Want the same engine running inside your own AWS account, so documents never
> leave it? That is the container product, **Data Guard (MCP Server)** - see
> [`mcp/container/data_guard.md`](../../mcp/container/data_guard.md). Both
> products run the same detection engine and return the same results.

---

## 1. What this product does

It gives your application or AI agent a deterministic way to find and remove
sensitive values before they reach a log, a third party, or a model's context.
The API lets you:

- Scan a document and report where sensitive values are, without changing it
- Redact a document under a named policy, returning an auditable receipt
- Reverse a reversible redaction, given the same key
- Gate a document against a compliance pack: pass or fail, with the violations
- Discover what the service detects and which compliance packs exist

Detection is deterministic - regular expressions, checksums, curated word lists,
and field-name rules. There is no ML model, so the same input gives the same
output on every call, and every finding names the rule that produced it.

Three properties hold on every call:

- **The service never echoes what it protects.** Findings return offsets and a
  masked preview, never the matched value. Error messages never quote your
  document either, so they are safe to log verbatim.
- **It fails closed.** Strategies are validated before a single character is
  rewritten, a malformed caller span is refused rather than clamped, and a
  restore is all-or-nothing.
- **Nothing about a request is retained.** The service stores no document and
  writes no copy. A redaction `key` you pass is used for that one call and is
  never stored, which also means a lost key cannot be recovered from us. API
  keys are stored only as a SHA-256 hash.

---

## 2. Prerequisites

- An AWS account and an active subscription to **Data Guard - PII, PHI, and
  Secret Redaction API** in AWS Marketplace.
- An HTTPS client: `curl`, Python, or any language with an HTTP library. No SDK
  is needed.
- For the AgentCore Gateway path only: Amazon Bedrock AgentCore available in
  your Region, and IAM permissions to create a gateway, a gateway target, and
  an API key credential provider.

---

## 3. Subscribe and get your API key

1. On the product's AWS Marketplace page, choose **View purchase options**, pick
   a contract term, and subscribe.
2. Choose **Set up your account**. AWS sends you to
   `https://cloud.llmlinq.com/aws/data-guard/register`.
3. **Sign in** to LLMLinq, or **Create an account**. The screen names the
   LLMLinq account the subscription will be attached to - check it, then confirm.
   An AWS account cannot be moved between LLMLinq accounts afterwards.
4. Wait for activation. The page shows the subscription as pending until AWS
   confirms the entitlement. Leave the page open; it finishes on its own.
5. **Copy the API key.** It starts with `llq_live_` and is shown **once**. Store
   it in a secret manager.

Your key, subscription state, and account details stay available at
`https://cloud.llmlinq.com/aws/data-guard/configure`.

**Lost the key?** Rotate it on the same configure page. The old key stops
working immediately. Only a hash of the key is stored, so it is replaced, never
recovered.

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

```bash
export DG_API_KEY="llq_live_..."

curl -X POST https://api.llmlinq.com/data-guard/v1/scan \
  -H "Authorization: Bearer $DG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "Call Sarah on 415-555-2671"}'
```

```json
{
  "request_id": "635da2d18b66440eb8b21c6687aa52a1",
  "document_kind": "text",
  "policy": "default",
  "summary": {"total": 1, "by_entity_type": {"PHONE_NUMBER": 1},
              "by_category": {"pii": 1}, "risk": "moderate"},
  "findings": [{"entity_type": "PHONE_NUMBER", "category": "pii", "path": null,
                "start": 14, "end": 26, "length": 12, "confidence": 1.0,
                "detector": "pattern+ctx:call", "preview": "***-***-2671"}]
}
```

A finding says **where** a value is, never what it is.

### 4.3 Client setup (Python)

Standard library only. Every example in section 6 uses this `call` helper.

```python
import json, os, urllib.error, urllib.request

BASE = "https://api.llmlinq.com/data-guard/v1"
API_KEY = os.environ["DG_API_KEY"]

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
        # Error bodies are {"error": "<code>", "message": "..."} - see section 8
        raise RuntimeError(f"{err.code} {err.read().decode()}") from None

def detectors(category=None):
    url = f"{BASE}/detectors" + (f"?category={category}" if category else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())
```

### 4.4 OpenAPI and interactive reference

These need no key, so you can read them before subscribing:

| | |
|---|---|
| Interactive reference | https://api.llmlinq.com/data-guard/v1/docs |
| OpenAPI 3.1 | https://api.llmlinq.com/data-guard/v1/openapi.yaml |
| OpenAPI for AgentCore Gateway | https://api.llmlinq.com/data-guard/v1/openapi-agentcore.json |

`openapi.yaml` works with Postman, Insomnia, Bruno, or `openapi-generator` for a
typed client.

---

## 5. Endpoint reference

Every `POST` endpoint takes a JSON body with the document supplied as **exactly
one** of:

- `text` - the document inline (plain text, JSON, NDJSON, YAML, CSV)
- `base64_data` - the document base64-encoded; use this for anything that is not
  UTF-8 text, or where byte-exactness matters

There is no file-path or `s3://` input over HTTP. A parameter an endpoint does
not accept is refused with `400 unsupported_parameters`, naming it, rather than
silently ignored.

Results are always returned inline, up to 256 KiB. See section 9 for sizes.

### 5.1 POST /scan

Find sensitive values without changing anything.

| Field | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` | string | - | provide exactly one |
| `kind` | string | `auto` | `auto`, `text`, `json`, `ndjson`, `yaml`, `csv` |
| `policy` | string | `default` | policy pack - decides which entities count |
| `entity_types` | string[] | all | restrict the scan to these entity types |
| `min_confidence` | number | policy's | 0.0 to 1.0; override the confidence threshold |
| `max_findings` | integer | `200` | cap on findings returned; `summary` still counts all |

Returns: `request_id`, `document_kind`, `policy`, `min_confidence`, `bytes`,
`origin`, `segments_scanned`, `summary` (`total`, `by_entity_type`,
`by_category`, `risk`), `findings`, `findings_truncated`, `document_truncated`.

Each finding carries `entity_type`, `category`, `path` (the JSONPath of the
field inside a structured document, such as `$.patient.ssn`, and `null` for
plain text), `start`, `end`, `length`, `confidence`, `detector`, and `preview`.

- `detector` is provenance: `luhn+ctx:card` means the digits passed a Luhn check
  **and** the word "card" was nearby.
- `preview` is masked, and is the only view of a matched value that ever leaves
  the service.
- `risk` is the highest category present: a secret is `critical`, PHI and
  financial data `high`, other PII `moderate`, nothing `none`.

### 5.2 POST /redact

Detect and rewrite. Structured documents are redacted value by value, so the
result still parses as valid JSON, NDJSON, YAML, or CSV.

| Field | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` | string | - | provide exactly one |
| `kind` | string | `auto` | document kind |
| `policy` | string | `default` | policy pack |
| `strategy` | string | policy's | override the strategy for every entity |
| `key` | string | - | required by `hash` and `encrypt`, and so by `gdpr_basic` |
| `entity_types` | string[] | all | restrict to these entity types |
| `min_confidence` | number | policy's | override the confidence threshold |
| `extra_spans` | object[] | - | spans you identified yourself |

Returns: `request_id`, `document_kind`, `policy`, `strategy_override`,
`delivery` (always `inline_text` over HTTP), `bytes`, `text`, `path` (always
`null` over HTTP), `receipt`, `reversible`, and the policy pack's `notes`.

`extra_spans` entries are objects with `start`, `end`, and `entity_type`
(character offsets into the exact text you sent, end exclusive). Use it for
values only you can recognise - an internal reference, or a person's name in
bare prose. Caller spans go through the same overlap resolution as detected
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

`by_source` splits redactions by the evidence behind them: the service's own
deterministic rules (`detected`), a model recognizer (`model`, always zero -
there is no model), and your `extra_spans` (`caller`). `input_sha256` lets
someone holding the original prove it produced this receipt, without the
receipt revealing anything about the document. Keep the receipt even when you
cannot keep the document.

### 5.3 POST /restore

Reverse a redaction produced with the `encrypt` strategy.

| Field | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` | string | - | provide exactly one |
| `key` | string | - | **required**; the same key used at redaction time |

Returns: `request_id`, `restored_count`, `delivery`, `bytes`, `text`.

Only `encrypt` is reversible. `label`, `mask`, `partial`, `hash`, `token`, and
`remove` are one-way by construction, and no key restores them. A restore is
all-or-nothing: if any placeholder fails to decrypt - wrong key, modified token,
or changed entity type - the call is refused and nothing partial comes back.
**The response contains the original sensitive values.**

### 5.4 POST /check

A gate: pass or fail a document against a compliance pack, changing nothing.
Use it before sending data to a third party, writing it to a log, or storing it.

| Field | Type | Default | Notes |
|---|---|---|---|
| `text` / `base64_data` | string | - | provide exactly one |
| `kind` | string | `auto` | document kind |
| `policy` | string | `hipaa_safe_harbor` | pack to check against |
| `min_confidence` | number | policy's | override the confidence threshold |

Returns: `request_id`, `policy` (the full pack description, including its own
`notes`), `document_kind`, `passed`, `violation_count`, `violations`, `summary`,
`document_truncated`. Each violation carries `entity_type`, `category`,
`count`, `max_confidence`, and up to 20 `locations` - locations only, never
values.

When the policy is `hipaa_safe_harbor`, the result also includes
`hipaa_identifiers`: the 18 identifiers from 45 CFR 164.514(b)(2) mapped to what
this service detects, with the three gaps stated explicitly.

### 5.5 GET /detectors

Discovery. No document, and it changes only when the service is released, so
call it once and cache it.

| Query parameter | Default | Notes |
|---|---|---|
| `category` | all | filter to `pii`, `phi`, `financial`, or `secret` |

Returns: `detectors` (one entry per entity type, with `entity_type`,
`category`, `detection`, `requires_context`, `description`, and `countries`),
`detector_count`, `categories`, `policies`, `strategies`, `document_kinds`, and
`notes`.

`requires_context: true` means the type needs a nearby cue word, or a field
name in structured input, and is missed when the value appears with no
surrounding text. Check this list before relying on a type you care about.

### 5.6 Policy packs

| Pack | Covers | Default strategy | Threshold |
|---|---|---|---|
| `default` | everything detectable | `label`, and `remove` for private keys | 0.50 |
| `hipaa_safe_harbor` | the 18 HIPAA Safe Harbor identifiers, 15 of which are covered | `label` | 0.40 |
| `pci_dss` | cardholder data | `mask`; CVV and PIN `remove`; expiry and name `label` | 0.50 |
| `gdpr_basic` | personal and financial data, pseudonymized | `hash` (requires a `key`) | 0.50 |
| `secrets_only` | credentials and API keys only | `label`, and `remove` for private keys | 0.50 |
| `strict_all` | every category, lowered bar, over-redacts by design | `remove` | 0.35 |

Three packs carry caveats in `notes`, which every response returns. Read them:
`gdpr_basic` notes that pseudonymized data is still personal data under GDPR,
`hipaa_safe_harbor` names the three identifiers it does not cover, and
`strict_all` states that its lowered threshold admits false positives on purpose.

### 5.7 Redaction strategies

| Strategy | What it leaves behind | Key |
|---|---|---|
| `label` | a readable `<ENTITY_TYPE>` marker | - |
| `mask` | asterisks, keeping the format and a four-character tail | - |
| `partial` | a type-specific fragment: an email domain, an IP subnet, the last four digits | - |
| `hash` | a deterministic keyed token; equal values stay equal, so joins survive | required |
| `token` | sequential `<ENTITY_1>`, `<ENTITY_2>` markers, stable within one document | - |
| `encrypt` | AES-GCM ciphertext, reversible by `/restore` | required |
| `remove` | nothing - the value is deleted | - |

`hash` and `encrypt` refuse to run without a key rather than producing output
that looks redacted but is not: an unkeyed hash of a nine-digit identifier falls
to a rainbow table in seconds. The key is stretched with HKDF-SHA256, so a
passphrase of any length works. It is never stored, so keep it in your own
secret manager, separate from the redacted output - anyone holding it can
re-link `hash` tokens and decrypt `encrypt` placeholders.

---

## 6. Examples

These use the `call` helper from section 4.3. Responses are abridged to the
fields each example is about; all sample data is synthetic.

### 6.1 Scan, then redact

```python
DOC = "Patient Sarah Chen, SSN 123-45-6789, card 4532 0151 1283 0366, key AKIAIOSFODNN7EXAMPLE"

call("scan", text=DOC)
# -> {"summary": {"total": 4,
#                 "by_category": {"financial": 1, "pii": 2, "secret": 1},
#                 "risk": "critical"},
#     "findings": [{"entity_type": "US_SSN", "category": "pii", "path": null,
#                   "start": 24, "end": 35, "length": 11, "confidence": 1.0,
#                   "detector": "us_ssn+ctx:ssn", "preview": "***-**-6789"}, ...]}

call("redact", text=DOC)
# -> {"text": "Patient <PERSON>, SSN <US_SSN>, card <CREDIT_CARD>, key <AWS_ACCESS_KEY_ID>",
#     "receipt": {"total_redactions": 4, "by_strategy": {"label": 4},
#                 "by_source": {"detected": 4, "model": 0, "caller": 0}}}
```

The same call with `curl`:

```bash
curl -X POST https://api.llmlinq.com/data-guard/v1/redact \
  -H "Authorization: Bearer $DG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "SSN 123-45-6789, key AKIAIOSFODNN7EXAMPLE", "policy": "default"}'
```

### 6.2 Structured documents stay parseable

JSON, NDJSON, YAML, and CSV are redacted value by value, so the result still
parses and each finding carries the field `path` it came from. A column named
`ssn` or a key named `name` is redacted because of its field name.

```python
RECORD = '{"patient": {"name": "Sarah Chen", "ssn": "123-45-6789", "email": "s.chen@northstar.example"}}'

call("scan", text=RECORD, kind="json")["findings"]
# -> paths: $.patient.email, $.patient.name, $.patient.ssn

print(call("redact", text=RECORD, kind="json", policy="hipaa_safe_harbor")["text"])
# {
#   "patient": {
#     "name": "<PERSON>",
#     "ssn": "<US_SSN>",
#     "email": "<EMAIL_ADDRESS>"
#   }
# }

CSV = "name,ssn,email\nSarah Chen,123-45-6789,s.chen@northstar.example\n"
call("redact", text=CSV, policy="hipaa_safe_harbor")
# -> {"document_kind": "csv",
#     "text": "name,ssn,email\n<PERSON>,<US_SSN>,<EMAIL_ADDRESS>\n"}
```

If parsing fails the service falls back to plain-text scanning rather than
erroring. That still catches anything with a recognizable shape, but loses
whatever was known only by its field name. Check the returned `document_kind`
whenever the document matters.

### 6.3 Gate against a compliance pack

```python
NOTE = "Discharge summary for Marcus Delacroix, MRN 4820193, DOB 1974-03-12."

res = call("check", text=NOTE, policy="hipaa_safe_harbor")
# -> {"passed": false, "violation_count": 2,
#     "violations": [{"entity_type": "MEDICAL_RECORD_NUMBER", "category": "phi",
#                     "count": 1, "max_confidence": 0.85,
#                     "locations": [{"path": null, "start": 44}]},
#                    {"entity_type": "DATE_OF_BIRTH", "category": "pii",
#                     "count": 1, "max_confidence": 0.85,
#                     "locations": [{"path": null, "start": 57}]}]}

if not res["passed"]:
    NOTE = call("redact", text=NOTE, policy="hipaa_safe_harbor")["text"]
```

Note what is *not* in that list: "Marcus Delacroix" has no title, label, or
field name in front of it, so it is not detected - see 6.6.

### 6.4 Reversible redaction

`encrypt` is the only reversible strategy - use it when a downstream system must
process a document it is not allowed to read.

```python
KEY = "a-passphrase-from-your-secret-manager"

red = call("redact", text="SSN 123-45-6789", strategy="encrypt", key=KEY)
# -> {"reversible": true, "text": "SSN <US_SSN:enc:g80a75wo_eHujlp5M6o_J04m...>"}

call("restore", text=red["text"], key=KEY)
# -> {"restored_count": 1, "text": "SSN 123-45-6789"}
```

### 6.5 Pseudonymize so joins survive

`hash` gives a deterministic keyed token: the same value yields the same token
under the same key, so two datasets still join on the redacted column while
neither reveals the value. This is what `gdpr_basic` uses.

```python
orders  = "customer_email,total\ns.chen@northstar.example,412.00\n"
support = "customer_email,tickets\ns.chen@northstar.example,3\n"

call("redact", text=orders,  policy="gdpr_basic", key=KEY)
# -> {"text": "customer_email,total\n<EMAIL_ADDRESS:79f07ff29115>,412.00\n"}

call("redact", text=support, policy="gdpr_basic", key=KEY)
# -> {"text": "customer_email,tickets\n<EMAIL_ADDRESS:79f07ff29115>,3\n"}
```

Same key, same token, so the join holds. A different key gives a different
token, which is how you scope re-linkability per tenant or retention period.
Without `key`, the call is refused with `400 invalid_request`.

### 6.6 Supply spans the rules cannot reach

```python
call("redact", text="Then Delacroix mentioned the invoice.",
     extra_spans=[{"start": 5, "end": 14, "entity_type": "PERSON"}])
# -> {"text": "Then <PERSON> mentioned the invoice.",
#     "receipt": {"by_source": {"detected": 0, "model": 0, "caller": 1}}}
```

`by_source` keeps the two apart on purpose: `detected` is a rule an auditor can
re-check, `caller` is your claim. A span outside the text is refused, not
clamped. `entity_type` can be any name, including your own, such as
`INTERNAL_REF`.

### 6.7 Tune what counts as a finding

```python
LOG = "user=s.chen@northstar.example ip=10.2.14.9 key=AKIAIOSFODNN7EXAMPLE"

# Only these entity types
call("redact", text=LOG, entity_types=["AWS_ACCESS_KEY_ID"])["text"]
# -> "user=s.chen@northstar.example ip=10.2.14.9 key=<AWS_ACCESS_KEY_ID>"

# Credentials only, for log scrubbing
call("redact", text=LOG, policy="secrets_only")["text"]
# -> "user=s.chen@northstar.example ip=10.2.14.9 key=<AWS_ACCESS_KEY_ID>"

# Keep the shape of the data for debugging
call("redact", text=LOG, strategy="partial")["text"]
# -> "user=s*****@northstar.example ip=10.2.*.* key=****************MPLE"

# Stable per-document tokens
call("redact", text=LOG, strategy="token")["text"]
# -> "user=<EMAIL_ADDRESS_1> ip=<IP_ADDRESS_1> key=<AWS_ACCESS_KEY_ID_1>"

# Raise the bar to cut false positives
call("scan", text=LOG, min_confidence=0.9)
```

### 6.8 Discover coverage

```python
cat = detectors(category="secret")
[d["entity_type"] for d in cat["detectors"]][:3]
# -> ["ANTHROPIC_API_KEY", "AUTHORIZATION_HEADER", "AWS_ACCESS_KEY_ID"]
```

---

## 7. Use it from an Amazon Bedrock AgentCore Gateway

An AgentCore Gateway turns these REST endpoints into MCP tools for your agents,
and holds the API key so it never reaches the model.

### 7.1 Store the API key

In the AgentCore console, open **Identity** and create an **API key** credential
provider holding your `llq_live_...` key.

### 7.2 Create a gateway

Create a gateway with the inbound authorization your agents already use
(JWT or IAM).

### 7.3 Add a target

| Field | Value |
|---|---|
| Target protocol | **MCP target** |
| Target type | **REST API** (`OPEN_API_SCHEMA` in the API) |
| Schema | the contents of `openapi-agentcore.json`, pasted inline (or uploaded to S3) |
| Outbound auth | the API key credential provider from 7.1, credential location **HEADER**, header name `Authorization` |

Download the schema first - the target accepts it inline or from an `s3://`
URI, **not** from an HTTPS URL:

```bash
curl -s -o openapi-agentcore.json \
  https://api.llmlinq.com/data-guard/v1/openapi-agentcore.json
```

Use `openapi-agentcore.json`, not `openapi.yaml`: the readable spec uses
`allOf`, which the gateway rejects.

Two mistakes produce confusing errors:

- **Target type "MCP server" is wrong.** This API speaks REST; the gateway is
  what makes it MCP. With "MCP server" the gateway attempts an MCP `initialize`
  handshake against the URL and reports `HTTP 404 to the initialize handshake`,
  which looks like the API is down when the target type is simply wrong.
- **The target keeps a copy of the schema.** When a new API version adds or
  changes fields, re-download and re-paste it. If you update the target through
  the API (`update-gateway-target`), include the credential configuration again
  - the update is a full replacement and otherwise detaches the API key.

The `Bearer` prefix is optional: the API accepts the key with or without it.

### 7.4 Tools your agent sees

Tool names are prefixed with your target name:

```
<target>___scan        <target>___redact     <target>___restore
<target>___check       <target>___listDetectors
```

Arguments are the same as the request bodies in section 5. The gateway
validates arguments against the schema and drops any it does not declare.

A good default instruction for the calling agent: call `scan` first to see what
is present, then `redact` with the policy pack that matches your regime.

If a tool result contains `401 api_key_required`, the key is not reaching the
API: check the credential provider is attached to the target.

---

## 8. Errors

Errors are JSON: `{"error": "<code>"}`, plus `message` where it helps. Branch on
`error`, not on `message`. Messages never quote your document.

| Status | `error` | Meaning and fix |
|---|---|---|
| 400 | `invalid_json` | The body is not a JSON object. |
| 400 | `unsupported_parameters` | A field this endpoint does not accept; `parameters` lists them. `path` is never accepted over HTTP. |
| 400 | `invalid_request` | A field has the wrong value or shape, both `text` and `base64_data` were sent, a keyed strategy has no `key`, or a restore failed. `message` says what to change. |
| 401 | `api_key_required` | No key, or a value that is not a Data Guard key. |
| 401 | `invalid_api_key` | A key we did not issue, or one that has been rotated. |
| 403 | `subscription_inactive` | The key is valid but the subscription is not active (`state` says why). Fixed in AWS Marketplace, not with a new key. |
| 404 | `not_found` | Unknown path or method. |
| 413 | `result_too_large` | The result exceeds 256 KiB. Redaction can grow a document; split it. |
| 429 | - | Throttled. Retry with exponential backoff. |
| 500 | `internal_error` | An unexpected fault. Retry; if it persists, contact support. |

A successful `POST` returns a `request_id`; an error does not. When contacting
support, quote the `request_id`, or the error code and the time of the call -
we cannot see your document.

---

## 9. Limits and behavior

| Limit | Value |
|---|---|
| Request body | about 6 MB (the AWS Lambda synchronous invocation limit) |
| Response | up to 256 KiB, always inline; larger results are `413 result_too_large` |
| Rate | 100 requests/second per endpoint across the service, with bursts to 200 |
| Document walk | 200,000 leaf values, after which `document_truncated` is set |

- Inputs are refused, never silently truncated. Split large documents into
  pieces - one NDJSON line or one CSV chunk per request works well.
- The service is stateless. No key, counter, or document survives a call.
- **Unparseable structured input falls back to plain-text scanning** rather than
  failing. Plain text carries no field names, so a value with a recognizable
  shape (an SSN, a card number) is still caught, while a value known only by its
  key - a bank account number, an employee ID, a name in a column - is lost.
  If a document matters, pass `kind` explicitly and check the returned
  `document_kind`.
- **Person names in bare prose, with no title, label, role cue, or field name,
  are not detected.** "Dr. Chen", "Patient Marcus Delacroix", and a `name`
  column are found; "...then Delacroix mentioned it" is not. Supply those spans
  through `extra_spans`.
- `document_truncated: true` means the document was only partly examined.
  Treat it as a failure for anything that must be fully redacted.

### 9.1 Billing

The subscription is a contract (monthly or annual) plus usage, billed through
AWS Marketplace. Current prices are on the listing page. Usage is measured on
two dimensions:

- **API calls**, per 1,000 successful calls.
- **Document volume**, per GB of request body submitted.

Only calls that the service answers successfully are counted. A `400`, `401`,
`403`, or `413` is not billed. Your subscription state is shown at
`https://cloud.llmlinq.com/aws/data-guard/configure`, and billed usage appears
in the AWS Billing console.

A contract cannot be cancelled mid-term from the console. Turn off auto-renewal
to stop further billing, and see the refund policy on the listing.

### 9.2 What this product does and does not claim

This service supports de-identification under the HIPAA Safe Harbor method and
covers 15 of the 18 identifiers; the other three - web URLs, biometric
identifiers, and full-face photographs - are listed in the `hipaa_safe_harbor`
pack's own notes and returned by `/check`. It is one control among many, so it
does not by itself make a program "HIPAA compliant". Likewise, `gdpr_basic`
pseudonymizes personal data under Article 4(5), which reduces risk but does not
take the data out of GDPR scope. And no detector finds all PII - the name
limitation above is the documented example.

Your documents are sent to and processed on the service's infrastructure, in
memory, and are not retained. If your data must never leave your own AWS
account, use the container product instead.

---

## 10. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `401 api_key_required` | No `Authorization` or `X-Api-Key` header, or the value does not start with `llq_live_`. |
| `401 invalid_api_key` | The key was rotated or mistyped. Copy the current key, or rotate it at `cloud.llmlinq.com/aws/data-guard/configure`. |
| `403 subscription_inactive` | The subscription has ended, or has not finished activating. Check AWS Marketplace and the configure page. |
| Setup page shows "We could not confirm that subscription" | Start again from **Set up your account** in the AWS Marketplace console; the setup link is single-use and expires. |
| `400 unsupported_parameters` with `path` | File paths are not accepted over HTTP. Send the content as `text` or `base64_data`. |
| `400` "The 'hash' strategy requires a key" | Pass `key`. `gdpr_basic` uses `hash`, so it needs one too. |
| `400` "No encrypted placeholders were found" | `/restore` only reverses `encrypt` output, which looks like `<US_SSN:enc:...>`. |
| `400` "Could not restore ... no changes were applied" | The key differs from the one used at redaction time, or a placeholder was modified. |
| `413 result_too_large` | Split the document and send it in pieces. |
| Request fails for a very large document before reaching the API | The body is over the ~6 MB request limit. Split it. |
| Fewer findings than expected in JSON or CSV | The document may have failed to parse and been scanned as text. Check `document_kind`, and pass `kind` explicitly. |
| A person's name was not redacted | Expected when the name has no surrounding cue. Supply it through `extra_spans`. |
| More findings than expected | Narrow with `entity_types`, or raise `min_confidence`. `strict_all` over-redacts by design. |
| AgentCore Gateway: `HTTP 404 to the initialize handshake` | Target type is "MCP server". Recreate it as **REST API** (section 7.3). |
| AgentCore Gateway: `401 api_key_required` in a tool result | Attach the API key credential provider to the target, location HEADER. |
| `429` | You are over the rate limit. Retry with exponential backoff. |

---

## 11. Support

Email **contact@infoinlet.com**. We reply within one business day, Monday to
Friday.

Include your AWS account ID, and for a question about a specific call, the
`request_id` from a successful response (or the error code and time). That lets
us trace the call without you sending us the data. Never include your API key,
redaction keys, or real sensitive values.

Billing, cancellation, and refunds run through AWS Marketplace; see the refund
policy on the listing.
