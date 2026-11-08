# Data handling and limits

[Data Guard MCP Server](README.md) > Data handling and limits

## Where your data goes

- **Nowhere outside your AWS account.** The server runs on AgentCore Runtime in
  your account, makes no outbound calls and sends nothing to us.
- **Nothing is kept between calls.** The server is stateless.
- **No key is ever stored**: not in the image, the receipt or the audit log.
- **Responses never echo a matched value.** Findings carry offsets and a masked
  preview. `restore_data` is the one exception, by design: it returns the
  originals, and only inline.
- **No plaintext on disk.** Large redacted results go to the scratch
  directory; restored originals never do.
- **The audit log**, if you turn it on, holds counts, hashes and rule names
  only. See [Configuration](configuration.md#audit-log).

## How it behaves

- **Deterministic.** Checksums, patterns, field-name rules and word lists. No ML
  model, so every finding names its rule and can be re-checked.
- **Fails closed.** Strategies are checked before anything is rewritten, a bad
  span is refused rather than clamped, a restore is all-or-nothing, and an
  oversized input is refused rather than truncated.

## Known detection limits

- **Names with no cue are not detected.** "Dr. Chen", "Patient Marcus
  Delacroix" and a `name` column are found; "...then Delacroix mentioned it" is
  not. Pass such spans in `extra_spans`.
- **Unparseable structured input is scanned as plain text.** Values with a
  recognizable shape (an SSN, a card) are still caught; values known only by
  their field name (a bank account number, an employee ID) are not. Pass `kind`
  and check the returned `document_kind`.
- **Some types need a cue.** Those with `requires_context: true` in
  `list_detectors` are missed without a nearby keyword or field name.

## What it does and does not claim

- **HIPAA:** supports de-identification under the Safe Harbor method and covers
  15 of the 18 identifiers. Not covered: web URLs, biometric identifiers and
  full-face photographs. It is one control among many and does not by itself
  make a program "HIPAA compliant".
- **GDPR:** `gdpr_basic` pseudonymizes (Article 4(5)). Pseudonymized data is
  still personal data.
- **Coverage:** no detector finds all PII. The limits above are the documented
  examples.
