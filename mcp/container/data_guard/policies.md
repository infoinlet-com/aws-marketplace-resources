# Policies and strategies

[Data Guard MCP Server](README.md) > Policies and strategies

A **policy pack** decides which entity types count and how each is redacted. A
**strategy** is what replaces a value. Pick a pack with `policy`; override its
strategy for every entity with `strategy`.

## Pick a pack

| `policy` | Use it for | Redacts with | Threshold |
|---|---|---|---|
| `default` | Everything detectable | `label`; private keys `remove` | 0.50 |
| `hipaa_safe_harbor` | Health data: 15 of the 18 Safe Harbor identifiers | `label` | 0.40 |
| `pci_dss` | Cardholder data | card `mask`; CVV and PIN `remove`; expiry and name `label` | 0.50 |
| `gdpr_basic` | Personal data you still need to join on | `hash` (needs `key`) | 0.50 |
| `secrets_only` | Logs: credentials and API keys only | `label`; private keys `remove` | 0.50 |
| `strict_all` | Over-redact on purpose | `remove` | 0.35 |

The threshold is the minimum confidence a finding needs. Override it per call
with `min_confidence`.

Every response returns the pack's `notes`. Three packs carry caveats there:

- `hipaa_safe_harbor` names the three identifiers it does not cover: web URLs,
  biometric identifiers and full-face photographs.
- `gdpr_basic`: pseudonymized data is still personal data under GDPR.
- `strict_all`: its lower threshold produces false positives by design.

`pci_dss` example: `Card 4532 0151 1283 0366 exp 11/29 CVV 318` becomes
`Card **** **** **** 0366 exp <CARD_EXPIRY> CVV `.

## Strategies

| `strategy` | What replaces the value | Example | Needs `key` |
|---|---|---|---|
| `label` | the entity type | `<US_SSN>` | - |
| `mask` | asterisks, keeping the format and the last four | `***-**-6789` | - |
| `partial` | a type-specific fragment: email domain, IP subnet, last four | `s*****@northstar.example` | - |
| `token` | a numbered marker, stable within one document | `<EMAIL_ADDRESS_1>` | - |
| `hash` | a keyed token; same value and key, same token | `<EMAIL_ADDRESS:79f07ff29115>` | yes |
| `encrypt` | AES-GCM ciphertext, reversible with `restore_data` | `<US_SSN:enc:...>` | yes |
| `remove` | nothing | | - |

Only `encrypt` can be reversed. All the others are one-way.

## Keys

`hash` and `encrypt` (and so `gdpr_basic`) refuse to run without a key, rather
than return output that only looks redacted: an unkeyed hash of a 9-digit number
is reversed in seconds.

- Pass `key` on the call, or set `DG_TOKEN_KEY` on the runtime as a default. Any passphrase works; it is stretched with HKDF-SHA256.
- **It is never stored**, not in the image, the receipt or the audit log. A lost key cannot be recovered, and `encrypt` output
  made with it cannot be restored.
- Keep it in your own secret manager, apart from the redacted data. Anyone with
  the key can re-link `hash` tokens and decrypt `encrypt` placeholders.
- Use a different key per tenant or retention period to keep their tokens
  apart.

## Receipts

Every `redact_data` call returns a receipt: counts and hashes only, safe to log and keep
when you cannot keep the document.

```json
{
  "policy": "default",
  "input_sha256": "db8656ed...",
  "input_bytes": 111,
  "document_kind": "text",
  "total_redactions": 4,
  "by_entity_type": {"CONNECTION_STRING_PASSWORD": 1, "CREDIT_CARD": 1, "PERSON": 1, "US_SSN": 1},
  "by_category": {"financial": 1, "pii": 2, "secret": 1},
  "by_strategy": {"label": 4},
  "by_source": {"detected": 4, "model": 0, "caller": 0},
  "min_confidence": 0.5,
  "truncated": false
}
```

- `by_source`: `detected` is the server's own rules; `caller` is spans you
  passed in `extra_spans`; `model` is always 0 (there is no model).
- `input_sha256` lets whoever holds the original prove it matches this receipt,
  without the receipt revealing anything.
