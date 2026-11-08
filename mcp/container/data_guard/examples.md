# Examples

[Data Guard MCP Server](README.md) > Examples

Each example assumes you finished [Getting started](getting-started.md) and
have a runtime ARN. Responses are trimmed to the fields that matter; all sample
data is synthetic.

[Connect](#connect) | [Scan, then redact](#scan-then-redact) |
[JSON and CSV](#json-and-csv-stay-valid) | [Compliance gate](#gate-on-a-compliance-pack) |
[Reversible](#reversible-redaction) | [Joinable pseudonyms](#pseudonyms-that-still-join) |
[Your own spans](#redact-what-the-rules-cannot-see) | [Large files](#large-files) |
[Tuning](#tune-what-is-redacted)

---

## Connect

The runtime's MCP endpoint is:

```
https://bedrock-agentcore.<region>.amazonaws.com/runtimes/<url-encoded-runtime-arn>/invocations?qualifier=DEFAULT
```

URL-encode the whole ARN (`:` and `/` included). Requests are signed with AWS
SigV4, service `bedrock-agentcore`, unless you configured a JWT authorizer, in
which case send `Authorization: Bearer <token>`.

**Agent frameworks**: point the framework's MCP client (streamable HTTP
transport) at that URL with SigV4 signing. The five tools appear through
`tools/list`. A good instruction for the agent: call `scan_data` first, then
`redact_data` with the pack that matches your regime.

**Python** (`pip install boto3`). The examples below use this `tool` helper.

```python
import json, urllib.parse, urllib.request
import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

REGION = "us-east-1"
ARN = "arn:aws:bedrock-agentcore:us-east-1:<account>:runtime/<runtime-id>"
URL = (f"https://bedrock-agentcore.{REGION}.amazonaws.com/runtimes/"
       f"{urllib.parse.quote(ARN, safe='')}/invocations?qualifier=DEFAULT")
CREDS = boto3.Session().get_credentials().get_frozen_credentials()

def rpc(method, params=None):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
    req = AWSRequest(method="POST", url=URL, data=body,
                     headers={"Content-Type": "application/json",
                              "Accept": "application/json, text/event-stream"})
    SigV4Auth(CREDS, "bedrock-agentcore", REGION).add_auth(req)
    raw = urllib.request.urlopen(urllib.request.Request(
        URL, data=body.encode(), headers=dict(req.headers), method="POST"), timeout=60).read().decode()
    for line in raw.splitlines():          # the response may arrive as server-sent events
        if line.startswith("data: "):
            return json.loads(line[6:])
    return json.loads(raw)

def tool(name, **arguments):
    result = rpc("tools/call", {"name": name, "arguments": arguments})["result"]
    if result.get("isError"):
        raise RuntimeError(result["content"][0]["text"])
    return json.loads(result["content"][0]["text"])

print([t["name"] for t in rpc("tools/list")["result"]["tools"]])
```

---

## Scan, then redact

```python
DOC = ("Patient Sarah Chen, SSN 123-45-6789, card 4532 0151 1283 0366, "
       "db postgres://app:Tr0ub4dor-3@db.internal/orders")

tool("scan_data", text=DOC)["summary"]
# {"total": 4, "by_category": {"financial": 1, "pii": 2, "secret": 1}, "risk": "critical"}

tool("redact_data", text=DOC)["text"]
# "Patient <PERSON>, SSN <US_SSN>, card <CREDIT_CARD>,
#  db postgres://app:<CONNECTION_STRING_PASSWORD>@db.internal/orders"
```

Each finding from `scan_data` carries a masked `preview` (`***-**-6789`) and a
`detector` naming the rule, such as `luhn+ctx:card`: the digits passed a Luhn
check and the word "card" was nearby.

## JSON and CSV stay valid

Structured documents are redacted value by value, and a field named `ssn` or
`name` is redacted because of its name.

```python
CSV = "name,ssn,email\nSarah Chen,123-45-6789,s.chen@northstar.example\n"

tool("redact_data", text=CSV, policy="hipaa_safe_harbor")["text"]
# "name,ssn,email\n<PERSON>,<US_SSN>,<EMAIL_ADDRESS>\n"
```

Pass `kind` when you know it, and check the returned `document_kind`: a
document that fails to parse is scanned as plain text, which loses values known
only by their field name.

## Gate on a compliance pack

```python
NOTE = "Discharge summary for Marcus Delacroix, MRN 4820193, DOB 1974-03-12."

res = tool("check_policy", text=NOTE, policy="hipaa_safe_harbor")
# {"passed": false, "violation_count": 2,
#  "violations": [{"entity_type": "MEDICAL_RECORD_NUMBER", "locations": [{"start": 44}], ...},
#                 {"entity_type": "DATE_OF_BIRTH", "locations": [{"start": 57}], ...}]}

if not res["passed"]:
    NOTE = tool("redact_data", text=NOTE, policy="hipaa_safe_harbor")["text"]
```

"Marcus Delacroix" is not flagged: it has no title, label or field name in
front of it. See [Redact what the rules cannot see](#redact-what-the-rules-cannot-see).

## Reversible redaction

```python
KEY = "a-passphrase-from-your-secret-manager"   # or set DG_TOKEN_KEY on the runtime

red = tool("redact_data", text="SSN 123-45-6789", strategy="encrypt", key=KEY)
# red["text"] == "SSN <US_SSN:enc:...>"

tool("restore_data", text=red["text"], key=KEY)["text"]
# "SSN 123-45-6789"
```

All-or-nothing: with a wrong key or a modified placeholder, nothing partial
comes back. Restored text is always returned inline, never written to disk.

## Pseudonyms that still join

`hash` gives the same token for the same value and key, so datasets still join
on the redacted column. This is what `gdpr_basic` does.

```python
tool("redact_data", text="customer_email,total\ns.chen@northstar.example,412.00\n",
     policy="gdpr_basic", key=KEY)["text"]
# "customer_email,total\n<EMAIL_ADDRESS:79f07ff29115>,412.00\n"
```

## Redact what the rules cannot see

When your agent can see a value the rules miss, such as a name in bare prose,
pass it as a span:

```python
tool("redact_data", text="Then Delacroix mentioned the invoice.",
     extra_spans=[{"start": 5, "end": 14, "entity_type": "PERSON"}])
# text: "Then <PERSON> mentioned the invoice."
# receipt.by_source: {"detected": 0, "model": 0, "caller": 1}
```

`extra_spans` works with inline input (`text`, `base64_data`) only.

## Large files

`path` reads a file on the container's filesystem. A redacted result over
256 KiB is written to the scratch directory and only its path comes back, so
large output never floods the model's context.

```python
res = tool("redact_data", path="/tmp/exports/customers.ndjson", kind="ndjson")
# {"delivery": "path", "path": "/tmp/data-guard/redacted.ndjson",
#  "receipt": {"total_redactions": 12000, ...}}
```

Read `delivery` (`inline_text` or `path`) rather than assuming.

## Tune what is redacted

```python
LOG = "user=s.chen@northstar.example ip=10.2.14.9 db=postgres://app:Tr0ub4dor-3@db.internal/orders"

tool("redact_data", text=LOG, policy="secrets_only")["text"]   # credentials only
# "user=s.chen@northstar.example ip=10.2.14.9 db=postgres://app:<CONNECTION_STRING_PASSWORD>@db.internal/orders"

tool("redact_data", text=LOG, strategy="partial")["text"]      # keep the shape
# "user=s*****@northstar.example ip=10.2.*.* db=postgres://app:******dor-3@db.internal/orders"

tool("redact_data", text=LOG, policy="strict_all")["text"]     # over-redact on purpose
# "user= ip= db=postgres://app:@db.internal/orders"

tool("redact_data", text=LOG, entity_types=["EMAIL_ADDRESS"])  # only these types
tool("scan_data", text=LOG, min_confidence=0.9)                # fewer, surer findings
```
