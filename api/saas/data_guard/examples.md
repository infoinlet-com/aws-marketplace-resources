# Examples

[Data Guard API](README.md) > Examples

Each example assumes you finished [Getting started](getting-started.md) and have
your key in `DG_API_KEY`. Responses are trimmed to the fields that matter; all
sample data is synthetic.

[Client](#client) | [Scan, then redact](#scan-then-redact) |
[JSON and CSV](#json-and-csv-stay-valid) | [Compliance gate](#gate-on-a-compliance-pack) |
[Reversible](#reversible-redaction) | [Joinable pseudonyms](#pseudonyms-that-still-join) |
[Your own spans](#redact-what-the-rules-cannot-see) | [Tuning](#tune-what-is-redacted) |
[Coverage](#check-coverage)

---

## Client

**curl**

```bash
curl -X POST https://api.llmlinq.com/data-guard/v1/scan \
  -H "Authorization: Bearer $DG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "Call Sarah on 415-555-2671"}'
```

**Python**, standard library only. The examples below use this `call` helper.

```python
import json, os, urllib.error, urllib.request

BASE = "https://api.llmlinq.com/data-guard/v1"
HEADERS = {"Authorization": f"Bearer {os.environ['DG_API_KEY']}",
           "Content-Type": "application/json"}

def call(endpoint, **body):
    req = urllib.request.Request(f"{BASE}/{endpoint}", data=json.dumps(body).encode(),
                                 headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as err:   # body: {"error": "<code>", "message": "..."}
        raise RuntimeError(f"{err.code} {err.read().decode()}") from None
```

**Any other language**: generate a typed client from
[`openapi.yaml`](https://api.llmlinq.com/data-guard/v1/openapi.yaml) with
`openapi-generator`, or import it into Postman, Insomnia or Bruno.

---

## Scan, then redact

```python
DOC = ("Patient Sarah Chen, SSN 123-45-6789, card 4532 0151 1283 0366, "
       "db postgres://app:Tr0ub4dor-3@db.internal/orders")

call("scan", text=DOC)["summary"]
# {"total": 4, "by_category": {"financial": 1, "pii": 2, "secret": 1}, "risk": "critical"}

call("redact", text=DOC)["text"]
# "Patient <PERSON>, SSN <US_SSN>, card <CREDIT_CARD>,
#  db postgres://app:<CONNECTION_STRING_PASSWORD>@db.internal/orders"
```

Each finding from `/scan` carries a masked `preview` (`***-**-6789`) and a
`detector` naming the rule, such as `luhn+ctx:card`: the digits passed a Luhn
check and the word "card" was nearby.

## JSON and CSV stay valid

Structured documents are redacted value by value, and a field named `ssn` or
`name` is redacted because of its name.

```python
CSV = "name,ssn,email\nSarah Chen,123-45-6789,s.chen@northstar.example\n"

call("redact", text=CSV, policy="hipaa_safe_harbor")["text"]
# "name,ssn,email\n<PERSON>,<US_SSN>,<EMAIL_ADDRESS>\n"
```

Findings in JSON carry the field's `path`, such as `$.patient.ssn`.

Pass `kind` (`json`, `csv`, ...) when you know it, and check the returned
`document_kind`: a document that fails to parse is scanned as plain text, which
loses values known only by their field name.

## Gate on a compliance pack

`/check` passes or fails a document and changes nothing. Put it in front of a
log write, an export or a third-party call.

```python
NOTE = "Discharge summary for Marcus Delacroix, MRN 4820193, DOB 1974-03-12."

res = call("check", text=NOTE, policy="hipaa_safe_harbor")
# {"passed": false, "violation_count": 2,
#  "violations": [{"entity_type": "MEDICAL_RECORD_NUMBER", "locations": [{"start": 44}], ...},
#                 {"entity_type": "DATE_OF_BIRTH", "locations": [{"start": 57}], ...}]}

if not res["passed"]:
    NOTE = call("redact", text=NOTE, policy="hipaa_safe_harbor")["text"]
```

"Marcus Delacroix" is not flagged: it has no title, label or field name in
front of it. See [Redact what the rules cannot see](#redact-what-the-rules-cannot-see).

## Reversible redaction

`encrypt` is the only reversible strategy. Use it when a downstream system must
handle a document it may not read.

```python
KEY = "a-passphrase-from-your-secret-manager"

red = call("redact", text="SSN 123-45-6789", strategy="encrypt", key=KEY)
# red["text"] == "SSN <US_SSN:enc:...>"

call("restore", text=red["text"], key=KEY)["text"]
# "SSN 123-45-6789"
```

A restore is all-or-nothing: with a wrong key or a modified placeholder, it is
refused and nothing partial comes back.

## Pseudonyms that still join

`hash` turns each value into a keyed token. The same value and key always give
the same token, so two datasets still join on the redacted column. This is what
`gdpr_basic` does.

```python
call("redact", text="customer_email,total\ns.chen@northstar.example,412.00\n",
     policy="gdpr_basic", key=KEY)["text"]
# "customer_email,total\n<EMAIL_ADDRESS:79f07ff29115>,412.00\n"
```

A different key gives different tokens, so you can scope re-linking per tenant
or per retention period.

## Redact what the rules cannot see

A name in bare prose, or your own internal reference, can be passed as a span
(character offsets into the text you send, end exclusive):

```python
call("redact", text="Then Delacroix mentioned the invoice.",
     extra_spans=[{"start": 5, "end": 14, "entity_type": "PERSON"}])
# text: "Then <PERSON> mentioned the invoice."
# receipt.by_source: {"detected": 0, "model": 0, "caller": 1}
```

The receipt counts your spans as `caller`, apart from the service's own
`detected` findings. `entity_type` can be any name, such as `INTERNAL_REF`.

## Tune what is redacted

```python
LOG = "user=s.chen@northstar.example ip=10.2.14.9 db=postgres://app:Tr0ub4dor-3@db.internal/orders"

call("redact", text=LOG, policy="secrets_only")["text"]   # credentials only
# "user=s.chen@northstar.example ip=10.2.14.9 db=postgres://app:<CONNECTION_STRING_PASSWORD>@db.internal/orders"

call("redact", text=LOG, strategy="partial")["text"]      # keep the shape
# "user=s*****@northstar.example ip=10.2.*.* db=postgres://app:******dor-3@db.internal/orders"

call("redact", text=LOG, strategy="token")["text"]        # stable per-document tokens
# "user=<EMAIL_ADDRESS_1> ip=<IP_ADDRESS_1> db=postgres://app:<CONNECTION_STRING_PASSWORD_1>@db.internal/orders"

call("redact", text=LOG, entity_types=["EMAIL_ADDRESS"])  # only these types
call("scan", text=LOG, min_confidence=0.9)                # fewer, surer findings
```

## Check coverage

`GET /detectors` lists every entity type, pack and strategy. It changes only on
a release, so fetch it once and cache it.

```bash
curl "https://api.llmlinq.com/data-guard/v1/detectors?category=phi" \
  -H "Authorization: Bearer $DG_API_KEY"
```

`requires_context: true` on a type means it needs a nearby cue word, or a field
name in structured input. Check this before relying on a type.
