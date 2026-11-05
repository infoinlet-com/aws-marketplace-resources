# Your AWS account

[AI Cloud Gateway](README.md) > Your AWS account

Requests run in your AWS account through an IAM role you create with one
CloudFormation stack. Setup steps:
[Getting started](getting-started.md#3-connect-your-aws-account). Each
subscription connects one AWS account.

## What the stack creates

One IAM role, `AICloudGatewayRouter`. Only AI Cloud Gateway can assume it, and
only with the External ID unique to your subscription. It can:

- invoke Bedrock models and inference profiles (`bedrock:InvokeModel`,
  `bedrock:InvokeModelWithResponseStream`);
- list and describe them, read-only, so the dashboard can show which models you
  have enabled.

It cannot read or change anything else in your account, and has no AWS
Marketplace permissions, so it can never accept a model provider's terms for
you. Sessions last at most one hour.

## Enable more models

Amazon Nova, Meta Llama and OpenAI gpt-oss work on first use. Anthropic Claude
models need a one-time AWS Marketplace subscription in your account:

1. Sign in as an administrator (permission for `aws-marketplace:Subscribe`).
2. In the Bedrock console, in the connected region, open **Model catalog** and
   enable each model the dashboard lists, or try it once in the playground.
   AWS may ask a short use-case form for Anthropic models.
3. After a few minutes, choose **Test again** in the dashboard.

Until then, requests go to the models you already have. A request pinned to a
model not yet enabled fails with `403 bedrock_model_not_enabled`.

## Quotas

Bedrock quotas are your account's. If one model is throttled, the request moves
to the next; if all are, you get `429 bedrock_throttled`. Raise quotas in AWS
Service Quotas.

## Disconnect

Delete the stack. Calls then fail with `403 bedrock_access_denied`.
