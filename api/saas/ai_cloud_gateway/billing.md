# Billing

[AI Cloud Gateway](README.md) > Billing

You pay for two things, both through AWS:

- **Routing**, to AI Cloud Gateway through AWS Marketplace: your plan, plus
  requests beyond its monthly allowance.
- **Bedrock tokens**, to AWS in the AWS account you connected, at your Bedrock
  prices. AI Cloud Gateway adds no markup and does not resell tokens.

## Plans

Monthly or annual. Prices are on the listing's pricing tab.

| Plan | Routed requests included per month | Support |
|---|---|---|
| Starter | 50,000 | Email, next business day |
| Team | 1,000,000 | Faster email response |
| Business | 5,000,000 | Priority |

Every plan routes the same way and covers one connected AWS account.

## How usage is billed

- **Beyond the allowance, requests are billed per 1,000** at your plan's rate.
  A part-thousand is carried over until it completes.
- The allowance resets at 00:00 UTC on the first of each month. Unused requests
  do not carry over.
- **Only answered requests count.** Refused calls (`400`, `401`, `403`, `404`,
  or every model failing), including calls refused by a budget, and
  `GET /models` are free.
- A response your guardrail blocked (`finish_reason` `content_filter`) is an
  answered request, and counts.
- The dashboard's **Usage** page shows this month's allowance used and anything
  beyond it. Charges appear in the AWS Billing console of the subscribing
  account.

## Budgets and the allowance

They are different things:

- **The allowance** is how many routed requests your plan includes each month.
  Going past it does not stop anything; the extra requests are billed per
  1,000.
- **A [budget](controls.md#budgets)** is an optional limit you set. Once it is
  reached, requests are refused until the next month. It changes nothing in
  your plan or your allowance.

To keep routing charges close to your plan's fee, set a monthly request limit
on the subscription equal to your allowance. Requests already in flight when it
is reached can still go a little past it.

## Guardrails

If you [turn on a guardrail](controls.md#guardrails), AWS bills its usage to
your AWS account, like Bedrock tokens. AI Cloud Gateway adds no charge for it.

## Change or cancel

- **Upgrade** any time in AWS Marketplace; the larger allowance applies at once.
  Requests already used this month still count against it.
- **Downgrade** takes effect at renewal.
- **Cancel** by turning off auto-renewal; the plan runs to the end of its term.
  See the refund policy on the listing.
