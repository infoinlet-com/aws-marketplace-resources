# Data handling and limits

[Data Guard API](README.md) > Data handling and limits

## What is stored

- **Documents are never stored.** They are processed in memory to answer the
  call, in AWS `us-east-1`, and never written to a log, database or file.
- **Redaction keys are never stored.** A `key` is used for that one call. A lost
  key cannot be recovered from us.
- **API keys** are stored only as a SHA-256 hash.
- **Usage counters**: calls and bytes per subscription, for billing. No content.
- **Responses never echo a matched value.** Findings carry offsets and a masked
  preview; error messages never quote your document. `/restore` is the one
  exception, by design: it returns the originals.

If your documents must never leave your own AWS account, use the
[container product](../../../mcp/container/data_guard/README.md) instead. Same
engine, same results.

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
  `GET /detectors` are missed without a nearby keyword or field name.

## What it does and does not claim

- **HIPAA:** supports de-identification under the Safe Harbor method and covers
  15 of the 18 identifiers. Not covered: web URLs, biometric identifiers and
  full-face photographs. It is one control among many and does not by itself
  make a program "HIPAA compliant".
- **GDPR:** `gdpr_basic` pseudonymizes (Article 4(5)). Pseudonymized data is
  still personal data.
- **Coverage:** no detector finds all PII. The limits above are the documented
  examples.
