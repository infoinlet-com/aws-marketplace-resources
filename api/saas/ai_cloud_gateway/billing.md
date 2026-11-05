# Billing

[AI Cloud Gateway](README.md) > Billing

You pay for two things, both through AWS:

- **Routing**, to AI Cloud Gateway through AWS Marketplace: your plan, plus
  requests beyond its monthly allowance.
- **Bedrock tokens**, to AWS in the AWS account you connected, at your Bedrock
  prices. AI Cloud Gateway adds no markup and does not resell tokens.

## Plans

Monthly or annual. Prices are on the listing's pricing tab.

<!-- TO CONFIRM before publishing: allowances = AWS_MARKETPLACE_PLANS in aicloudgateway-webapp (docs/release/listing.md, "Plans"). -->
| Plan | Routed requests included per month | Support |
|---|---|---|
| Starter | 25,000 | Email, next business day |
| Team | 500,000 | Faster email response |
| Business | 5,000,000 | Priority |

Every plan routes the same way and covers one connected AWS account.

## How usage is billed

- **Beyond the allowance, requests are billed per 1,000** at your plan's rate.
  A part-thousand is carried over until it completes.
- The allowance resets at 00:00 UTC on the first of each month. Unused requests
  do not carry over.
- **Only answered requests count.** Refused calls (`400`, `401`, `403`, `404`,
  or every model failing) and `GET /models` are free.
- The dashboard's **Usage** page shows this month's allowance used and anything
  beyond it. Charges appear in the AWS Billing console of the subscribing
  account.

## Change or cancel

- **Upgrade** any time in AWS Marketplace; the larger allowance applies at once.
  Requests already used this month still count against it.
- **Downgrade** takes effect at renewal.
- **Cancel** by turning off auto-renewal; the plan runs to the end of its term.
  See the refund policy on the listing.
