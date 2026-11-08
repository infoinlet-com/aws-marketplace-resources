# Billing

[Data Guard API](README.md) > Billing

Everything is billed through AWS Marketplace, on the AWS account that
subscribed. Prices are on the listing's pricing tab.

## What you pay

- **A contract fee**, monthly or annual.
- **Usage beyond the monthly allowance**, on two dimensions:
  - **API calls**, per 1,000 successful calls.
  - **Document volume**, per GB of request body.

## The allowance

**The fee includes 25,000 API calls and 1 GB every month**, on monthly and
annual contracts alike.

- It resets at 00:00 UTC on the first of each month. Unused allowance does not
  carry over.
- Going past it does not stop anything; the extra usage is billed.
- The [configure page](https://cloud.llmlinq.com/aws/data-guard/configure)
  shows this month's use. Charges appear in the AWS Billing console.

## What counts

- **Only successful calls.** A `400`, `401`, `403`, `413` or `500` is free.
- `GET /detectors` is free.
- Over [MCP](ai-agents.md), a successful `scan_data`, `redact_data`,
  `restore_data` or `check_policy` is one API call. `list_detectors`,
  connecting and listing tools are free.
- Document volume is the size of the request body, parameters included.

## Free trial

30 days, one per AWS account. Not billed, and its usage is never reported to
AWS. It allows 10,000 API calls or 1 GB, whichever comes first, then answers
`403 trial_limit_reached`.

It does not turn into a paid subscription on its own. Subscribe from the listing
and choose **Set up your account** again; your API key stays the same. From the
moment the subscription is active, calls count against its allowance and the
trial limit no longer applies.

## Change or cancel

- A contract cannot be cancelled mid-term. **Turn off auto-renewal** in AWS
  Marketplace to stop at the end of the term.
- Refunds follow the refund policy on the listing.
