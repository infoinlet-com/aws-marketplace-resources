# Tools reference

[Data Guard MCP Server](README.md) > Tools reference

[Input](#input) | [list_detectors](#list_detectors) | [scan_data](#scan_data) |
[redact_data](#redact_data) | [restore_data](#restore_data) |
[check_policy](#check_policy) | [Errors](#errors) | [Limits](#limits)

## Input

Tools that read a document take **exactly one** of:

- `text`: the document inline (plain text, JSON, NDJSON, YAML, CSV)
- `base64_data`: the document base64-encoded
- `path`: a file on the container's filesystem

Common arguments:

| Argument | Default | Notes |
|---|---|---|
| `kind` | `auto` | `auto`, `text`, `json`, `ndjson`, `yaml`, `csv` |
| `policy` | `default` | a [policy pack](policies.md#pick-a-pack) |
| `min_confidence` | the pack's | 0.0 to 1.0 |
| `entity_types` | all | only these types (`scan_data`, `redact_data`) |

Results under 256 KiB return inline. A larger `redact_data` result is written to
the scratch directory and `path` comes back instead; `delivery` says which.

## list_detectors

Every entity type, pack, strategy and document kind. No document needed.
Optional `category`: `pii`, `phi`, `financial` or `secret`.

Each detector has `entity_type`, `category`, `detection`, `requires_context`,
`description` and `countries`. `requires_context: true` means the type needs a
nearby cue word or a field name, and is missed without one.

## scan_data

Find sensitive values without changing anything.

Extra argument: `max_findings` (default `200`, 1 to 5000).

Returns `summary` (`total`, `by_entity_type`, `by_category`, `risk`) and
`findings`, plus `request_id`, `document_kind`, `policy`, `bytes`,
`segments_scanned`, `findings_truncated` and `document_truncated`.

Each finding:

| Field | Meaning |
|---|---|
| `entity_type`, `category` | e.g. `US_SSN`, `pii` |
| `path` | JSONPath inside a structured document (`$.customer.email`); `null` for text |
| `start`, `end`, `length` | character offsets |
| `confidence` | 0.0 to 1.0 |
| `detector` | the rule and its evidence, e.g. `luhn+ctx:card` |
| `preview` | masked, e.g. `***-**-6789`. The only view of a value that ever leaves the server |

## redact_data

Detect and rewrite. JSON, NDJSON, YAML and CSV are rewritten value by value
and still parse.

| Extra argument | Notes |
|---|---|
| `strategy` | override the pack's [strategy](policies.md#strategies) for every entity |
| `key` | for `hash` and `encrypt`; defaults to `DG_TOKEN_KEY` |
| `extra_spans` | your own spans: `start`, `end`, `entity_type`, optional `path` and `confidence`. Inline input only |

Returns `text` or `path` (per `delivery`), `receipt` (see
[Receipts](policies.md#receipts)), `reversible`, the pack's `notes`, and
`request_id`, `document_kind`, `policy`, `bytes`.

## restore_data

Reverse a redaction made with `encrypt`. Takes the document and `key`
(defaults to `DG_TOKEN_KEY`).

Returns `text`, `restored_count`, `request_id`, `bytes`. The result holds the
original values, so it is always inline and never written to disk.
All-or-nothing: if any placeholder fails to decrypt, the call is refused.

## check_policy

Pass or fail a document against a pack; changes nothing. `policy` defaults to
`hipaa_safe_harbor`.

Returns `passed`, `violation_count`, `violations`, `summary`,
`document_truncated`, `request_id` and the full `policy` description. Each
violation has `entity_type`, `category`, `count`, `max_confidence` and up to 20
`locations` (never values). Under `hipaa_safe_harbor`, `hipaa_identifiers` maps
all 18 identifiers to what is covered, gaps included.

## Errors

A refused call is an MCP tool error (`isError: true`) whose message says what to
change, such as "Provide exactly one of text / base64_data / path" or "The
'hash' strategy requires a key". Messages never quote your document.

## Limits

| Limit | Value |
|---|---|
| Input | `DG_MAX_INPUT_BYTES` ([Configuration](configuration.md)). Larger is refused, never truncated |
| Inline result | 256 KiB; larger `redact_data` results go to a scratch file |
| Document walk | 200,000 values. Past that `document_truncated` is `true`: treat as a failure |

The server is stateless: AgentCore may send consecutive calls to different
instances, and nothing survives a call.
