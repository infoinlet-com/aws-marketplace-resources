# Getting started

[Data Guard API](README.md) > Getting started

Three steps, about 5 minutes. You need an AWS account and an HTTPS client such
as `curl`. No SDK.

## 1. Subscribe

On the AWS Marketplace listing, choose **View purchase options**, then either:

- pick a monthly or annual contract and subscribe, or
- choose **Try for free** for the [free trial](#free-trial).

## 2. Set up your account and copy the key

1. Choose **Set up your account**. AWS sends you to
   `cloud.llmlinq.com/aws/data-guard/register`.
2. Sign in, or create an account. The screen names the account the
   subscription will be attached to: check it, then confirm.
   An AWS account cannot be moved to another account afterwards.
3. Wait for activation, usually a minute or two. Leave the page open; it
   finishes on its own.
4. **Copy the API key.** It starts with `llq_live_` and is **shown once**.
   Store it in a secret manager.

Your key, subscription state and usage stay at
[cloud.llmlinq.com/aws/data-guard/configure](https://cloud.llmlinq.com/aws/data-guard/configure).
Lost the key? Rotate it there; the old one stops working immediately.

## 3. Make your first call

```bash
export DG_API_KEY="llq_live_..."

curl -X POST https://api.llmlinq.com/data-guard/v1/redact \
  -H "Authorization: Bearer $DG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "Call Sarah on 415-555-2671, SSN 123-45-6789"}'
```

```json
{
  "text": "Call Sarah on <PHONE_NUMBER>, SSN <US_SSN>",
  "receipt": {"total_redactions": 2, "by_entity_type": {"PHONE_NUMBER": 1, "US_SSN": 1}, "...": "..."},
  "...": "..."
}
```

Use `/scan` instead of `/redact` to see what is there without changing
anything. Each finding says **where** a value is, never what it is.

If you get an error instead:

| `error` | Go back to |
|---|---|
| `api_key_required`, `invalid_api_key` | Step 2: check the header and the key |
| `subscription_inactive` | Step 2: wait for activation, or check the subscription in AWS Marketplace |

Anything else: [Troubleshooting](troubleshooting.md).

## Free trial

- **30 days, one per AWS account, no charge** for the fee or for usage.
- **Allowance:** 10,000 API calls or 1 GB of request data, whichever comes
  first. The configure page shows how much is used. Past it, calls return
  `403 trial_limit_reached`; `GET /detectors` keeps working.
- **It does not convert on its own.** To continue, subscribe from the listing
  and choose **Set up your account** again, attaching it to the same account.
  Your API key stays the same.

## Next

- [Examples](examples.md) - redact JSON and CSV, gate on a compliance pack,
  reversible redaction.
- [AI agents and MCP](ai-agents.md) - use it from Claude, VS Code or an
  AgentCore Gateway.
- [Policies and strategies](policies.md) - choose a pack for your regime.
