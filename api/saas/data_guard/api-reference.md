# API reference

[Data Guard API](README.md) > API reference

[Authentication](#authentication) | [Input](#input) | [POST /scan](#post-scan) |
[POST /redact](#post-redact) | [POST /restore](#post-restore) |
[POST /check](#post-check) | [GET /detectors](#get-detectors) |
[Errors](#errors) | [Limits](#limits)

Base URL: `https://api.llmlinq.com/data-guard/v1`. The same reference is
[interactive](https://api.llmlinq.com/data-guard/v1/docs) and available as
[OpenAPI 3.1](https://api.llmlinq.com/data-guard/v1/openapi.yaml), no key needed.

## Authentication

Send your key in either header:

```
Authorization: Bearer llq_live_...
X-Api-Key: llq_live_...
```

`Authorization: llq_live_...` without `Bearer` also works. Rotate the key at
[cloud.llmlinq.com/aws/data-guard/configure](https://cloud.llmlinq.com/aws/data-guard/configure);
the old key stops working immediately.

## Input

Every `POST` takes a JSON body with the document as **exactly one** of:

- `text`: the document inline (plain text, JSON, NDJSON, YAML, CSV)
- `base64_data`: the document base64-encoded, for non-UTF-8 input or when byte
  exactness matters

A field an endpoint does not accept is refused with `400 unsupported_parameters`,
never silently ignored. There is no file-path or `s3://` input.

Common fields:

| Field | Default | Notes |
|---|---|---|
| `kind` | `auto` | `auto`, `text`, `json`, `ndjson`, `yaml`, `csv` |
| `policy` | `default` | a [policy pack](policies.md#pick-a-pack) |
| `min_confidence` | the pack's | 0.0 to 1.0 |
| `entity_types` | all | only these types (`/scan`, `/redact`) |

## POST /scan

Find sensitive values without changing anything.

Extra field: `max_findings` (default `200`, max `5000`): findings returned;
`summary` still counts all.

Returns `summary` (`total`, `by_entity_type`, `by_category`, `risk`) and
`findings`, plus `request_id`, `document_kind`, `policy`, `min_confidence`,
`bytes`, `segments_scanned`, `findings_truncated` and `document_truncated`.

Each finding:

| Field | Meaning |
|---|---|
| `entity_type`, `category` | e.g. `US_SSN`, `pii` |
| `path` | JSONPath inside a structured document (`$.patient.ssn`); `null` for text |
| `start`, `end`, `length` | character offsets |
| `confidence` | 0.0 to 1.0 |
| `detector` | the rule and its evidence, e.g. `luhn+ctx:card` |
| `preview` | masked, e.g. `***-**-6789`. The only view of a value that ever leaves the service |

`risk` is the highest category found: secret `critical`, PHI and financial
`high`, other PII `moderate`, nothing `none`.

## POST /redact

Detect and rewrite. JSON, NDJSON, YAML and CSV are rewritten value by value
and still parse.

| Extra field | Notes |
|---|---|
| `strategy` | override the pack's [strategy](policies.md#strategies) for every entity |
| `key` | required by `hash` and `encrypt`, and so by `gdpr_basic` |
| `extra_spans` | your own spans: `[{"start": 5, "end": 14, "entity_type": "PERSON"}]`, offsets into the text you sent, end exclusive |

Returns `text` (the redacted document), `receipt` (see
[Receipts](policies.md#receipts)), `reversible`, the pack's `notes`, and
`request_id`, `document_kind`, `policy`, `strategy_override`, `bytes`.

## POST /restore

Reverse a redaction made with `encrypt`. Fields: `text` or `base64_data`, and
`key` (required, the one used to redact).

Returns `text`, `restored_count`, `request_id`, `bytes`. **The response holds the
original sensitive values.** All-or-nothing: if any placeholder fails to
decrypt, the call is refused and nothing partial comes back.

## POST /check

Pass or fail a document against a pack; changes nothing. `policy` defaults to
`hipaa_safe_harbor`.

Returns `passed`, `violation_count`, `violations`, `summary`,
`document_truncated`, `request_id` and the full `policy` description. Each
violation has `entity_type`, `category`, `count`, `max_confidence` and up to 20
`locations` (never values). Under `hipaa_safe_harbor`, `hipaa_identifiers` maps
all 18 identifiers to what is covered, gaps included.

## GET /detectors

Every entity type, pack, strategy and document kind. Optional query
`category`: `pii`, `phi`, `financial` or `secret`. Changes only on a release, so
cache it.

Each detector has `entity_type`, `category`, `detection`, `requires_context`,
`description` and `countries`. `requires_context: true` means the type needs a
nearby cue word or a field name, and is missed without one.

## Errors

`{"error": "<code>", "message": "..."}`. Branch on `error`. Messages never quote
your document, so they are safe to log.

| Status | `error` | Meaning |
|---|---|---|
| 400 | `invalid_json` | The body is not a JSON object |
| 400 | `unsupported_parameters` | A field this endpoint does not take; `parameters` names it |
| 400 | `invalid_request` | A wrong value, both `text` and `base64_data`, a missing `key`, a failed restore, or a document over 2 MiB. `message` says what to change |
| 401 | `api_key_required` | No key, or not a Data Guard key |
| 401 | `invalid_api_key` | Unknown or rotated key |
| 403 | `subscription_inactive` | The subscription is not active; `state` says why. Fixed in AWS Marketplace, not with a new key |
| 403 | `trial_limit_reached` | The free trial's allowance is used; `limits` states it |
| 404 | `not_found` | Unknown path or method |
| 413 | `result_too_large` | The result is over 256 KiB. Split the document |
| 429 | - | Throttled. Retry with exponential backoff |
| 500 | `internal_error` | Retry; if it persists, contact support |

A successful call returns a `request_id`. Quote it to support.

## Limits

| Limit | Value |
|---|---|
| Document | 2 MiB in every format. Larger is a `400`, never truncated |
| Response | 256 KiB, always inline. Larger is `413 result_too_large` |
| Rate | 100 requests/second per endpoint, bursts to 200 |
| Document walk | 200,000 values. Past that `document_truncated` is `true`: treat as a failure |

Split large input into pieces: one NDJSON line or one CSV chunk per request
works well. The service is stateless; nothing survives a call.
