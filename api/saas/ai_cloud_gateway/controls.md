# Budgets and guardrails

[AI Cloud Gateway](README.md) > Budgets and guardrails

Both are optional and off by default. Changes take effect within about a
minute.

[Budgets](#budgets) | [Guardrails](#guardrails)

## Budgets

A budget stops requests once a monthly limit is reached. You can set two
limits, alone or together:

- **Monthly spend limit (USD)**: estimated Bedrock spend.
- **Monthly request limit**: answered requests.

### Set a budget

- **For the whole subscription:** on **Subscriptions**, in the **Monthly
  budget** card.
- **For one API key:** on **API keys**, choose **Budget** on the key's row.

Enter a limit and choose **Save limits**. Leave a field empty for no limit;
**Remove limits** clears both. Spend takes dollars and cents, requests a whole
number.

The subscription's budget and the key's budget both apply. The first limit
reached stops the request. Each budget shows this month's use against its
limits and the reset date.

### What counts

- Every answered request counts, whether or not a budget is set, so a budget
  set mid-month starts from the real month-to-date figure.
- **Spend is an estimate:** the request's tokens at Amazon Bedrock on-demand
  list prices for the model that answered. It does not reflect prompt caching,
  discounts, or the Priority and Flex service tiers. Your AWS bill is the final
  figure.
- Refused requests reach no model and do not count.

### When a limit is reached

Requests get `403 budget_exceeded`. The message names the limit and when
requests are accepted again:

```json
{"error": {"message": "This API key has reached its monthly budget of 1,000 requests. Requests are accepted again from 2026-12-01 00:00 UTC, or as soon as the budget is raised or removed in the dashboard.",
           "type": "permission_error", "param": null, "code": "budget_exceeded"}}
```

It is a `403`, not a `429`, so SDKs do not retry it.

- **A budget refuses once reached; it does not cut a request off.** The request
  that reaches the limit completes, and so do requests already in flight. Spend
  can go slightly past the limit.
- **The month is the calendar month in UTC.** Requests are accepted again at
  00:00 UTC on the first of the next month, or within about a minute of raising
  or removing the limit.

A budget is separate from your plan's monthly allowance. See
[Billing](billing.md#budgets-and-the-allowance).

## Guardrails

You can apply an
[Amazon Bedrock Guardrail](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html)
from your own AWS account to every routed request. It works the same for every
model the gateway picks.

### Turn on a guardrail

1. **Update your CloudFormation stack** to the latest template, if you created
   it before guardrail support. [How](aws-account.md#update-your-stack).
2. **Create the guardrail** in the Amazon Bedrock console, in the region you
   connected, and publish a version.
3. On **AWS account**, in **Bedrock Guardrail**, choose **Add a guardrail**.
   Enter the **Guardrail ID or ARN** and the **Version** (default `1`), and
   choose **Check and save**.

The dashboard checks the guardrail through your role before saving it. If the
check fails, nothing changes and your connection keeps working:

| Message | Fix |
|---|---|
| "Your AI Cloud Gateway CloudFormation stack is older than guardrail support" | Do step 1, then save again |
| "There is no guardrail ... with version ... in ..." | Check the id, version and region in the Amazon Bedrock console |
| "This guardrail is in ... of account ..." | Use a guardrail in the connected account and region |
| "This guardrail's status is ..." | Fix it in the Amazon Bedrock console, or choose another version |

Use a numbered version. `DRAFT` is accepted, but it changes whenever someone
edits the guardrail, so what runs may not be what you reviewed.

To stop, choose **Remove guardrail**.

### What it does to responses

- **A blocked prompt or answer is not an error.** You get `200` with the
  guardrail's blocked message as the content and `finish_reason`
  `content_filter`. It counts as a routed request, and its tokens count toward
  your budget.
- **Streaming:** each chunk is checked before it is sent, so blocked text never
  reaches your client. This adds some latency per chunk.
- **Errors caused by the guardrail are final.** The gateway does not fall back
  to another model, because every model would fail the same way:
  `403 bedrock_guardrail_denied` or `400 bedrock_guardrail_invalid`. See
  [Troubleshooting](troubleshooting.md#budgets-and-guardrails).

### Cost

AWS bills guardrail usage to your AWS account, at your Bedrock prices, like the
model calls. AI Cloud Gateway does not add to it.
