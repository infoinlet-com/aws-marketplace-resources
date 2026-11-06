# AI Cloud Gateway

An LLM router for Amazon Bedrock. Each chat request goes to the lowest-cost
Bedrock model expected to answer it well, and runs **in your own AWS account**:
AWS bills Bedrock usage to you at your prices, and AI Cloud Gateway bills only
for routing.

The choice is **deterministic**: a rules engine, not another model, picks in
milliseconds, and the same request always gets the same model.

It speaks the OpenAI Chat Completions format, so your existing SDK or agent
framework works by changing two settings:

- Base URL: `https://api.aicloudgateway.com/v1`
- API key: `acg_...` from the [dashboard](https://dashboard.aicloudgateway.com)

## Guides

**[Getting started](getting-started.md)** - **Start here.** Subscribe, create a
key, connect your AWS account and make your first call, in about 15 minutes.

**[Examples](examples.md)** - Code to copy: Python, JavaScript, LangChain,
streaming, tool calls, JSON output, images, and an agent on Bedrock AgentCore.

**[Troubleshooting](troubleshooting.md)** - Common problems by stage, their fix,
and how to reach support.

**[How routing works](routing.md)** - How a model is chosen, when to use
`auto:cost` or `auto:quality` or pin a model, and tags that steer the choice.

**[Budgets and guardrails](controls.md)** - Monthly limits on spend or requests,
per subscription or API key, and an Amazon Bedrock Guardrail on every request.

**[Your AWS account](aws-account.md)** - What the CloudFormation role can and
cannot do, enabling more Bedrock models, and disconnecting.

**[API reference](api-reference.md)** - Request fields, responses, headers,
limits, key rotation and every error code.

**[Billing](billing.md)** - Plans, monthly allowances, and what counts as a
billed request.

**[Data handling](data-handling.md)** - What is stored and what is not, for
security and compliance reviews.

## Support

**contact@infoinlet.com** - we reply within one business day, Monday to Friday.
