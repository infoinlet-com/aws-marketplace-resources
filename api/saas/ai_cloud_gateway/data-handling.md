# Data handling

[AI Cloud Gateway](README.md) > Data handling

- **Prompts and completions are never stored.** They pass through the gateway
  in memory, in AWS `us-east-1`, to and from Bedrock in your account, and are
  never written to a log, database or file.
- **Inference runs in your AWS account**, in the region you connected, under
  your account's Bedrock terms.
- **What is kept:** request and token counts per model per hour, and routing
  metadata (such as task type, difficulty score and the model chosen). It holds
  no prompt or response text, and powers the **Usage** page, billing and routing
  improvements.
- **Budgets:** month-to-date counters per subscription and per API key:
  requests, tokens and estimated cost. They hold no prompt or response text,
  and are deleted about 40 days after the month ends.
- **Guardrails:** the gateway sends your guardrail's id and version with each
  request and does not ask Bedrock for the guardrail trace, so the matched
  text is neither returned nor stored.
- **Credentials:** API keys are stored only as a hash. The gateway holds no
  long-lived credential for your account; it uses temporary credentials for
  your role, which require your External ID.
  [What the role can do](aws-account.md#what-the-stack-creates).

If your data must not pass through the US, note the `us-east-1` pass-through.
