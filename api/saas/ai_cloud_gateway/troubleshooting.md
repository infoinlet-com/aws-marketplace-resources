# Troubleshooting

[AI Cloud Gateway](README.md) > Troubleshooting

Every error code is also listed in the [API reference](api-reference.md#errors).

## Subscribing

| Problem | Fix |
|---|---|
| Error page after **Set up your account** | Start again from **Set up your account** in the AWS Marketplace console |
| Claim fails: linked to another account | Another dashboard account claimed it. Sign in with that one, or contact support |
| Stays `pending` for over an hour | Contact support with your AWS account ID |
| `403 subscription_inactive` | The subscription is pending, cancelled or expired. Check **Subscriptions** |

## Connecting your AWS account

| Message after **Test and save** | Fix |
|---|---|
| "We couldn't assume this role" | Wait for `CREATE_COMPLETE`, check the Role ARN, or relaunch the stack from the dashboard link |
| "The role works, but it can't list Amazon Bedrock models" | The role was edited, or Bedrock is not available to your account in that region |
| "This role is in AI Cloud Gateway's AWS account" | Use a role in your own AWS account |

## Calling the API

| Problem | Fix |
|---|---|
| `401 api_key_required` | Send `Authorization: Bearer acg_...` |
| `401 invalid_api_key` | The key is wrong or revoked. Create a new one on **API keys** |
| `403 bedrock_not_connected` | [Connect your AWS account](getting-started.md#3-connect-your-aws-account) |
| `403 bedrock_access_denied` | The AI Cloud Gateway stack (role `AICloudGatewayRouter-...`) was deleted or changed. Relaunch it from the dashboard |
| `429 bedrock_throttled` | Your Bedrock quotas are used up on every model. Retry with backoff, or raise them in AWS Service Quotas |
| Times out before any output | Use `stream: true` for long answers |
| `500` or `502` | Retry. If it persists, contact support |

## Models and routing

| Problem | Fix |
|---|---|
| `403 bedrock_model_not_enabled`, or Claude never answers | [Enable the models](aws-account.md#enable-more-models) the **AWS account** page lists |
| `404 model_not_found` | Use an id from `GET /models` |
| `400 no_eligible_model` | The input is too long, or needs images or tools no enabled model has. Trim it, or enable more models |
| Turns of one conversation answered by different models | Expected with `auto`. Pin a model to keep one |
| A tag had no effect (`x-acg-directives` missing) | Check the [tag rules](routing.md#tags) |

## Budgets and guardrails

| Problem | Fix |
|---|---|
| `403 budget_exceeded` | A monthly limit on the subscription or the key is reached; the message says which. Raise or remove it on **Subscriptions** or **API keys**, or wait for 00:00 UTC on the 1st. [Budgets](controls.md#budgets) |
| Spend went past the budget | Expected: the request that reaches the limit completes, and so do requests already in flight |
| Estimated spend differs from the AWS bill | Expected: the estimate uses on-demand list prices. Your AWS bill is the final figure |
| `403 bedrock_guardrail_denied` | Your role may not apply the guardrail. Relaunch the stack from **AWS account**, or choose **Remove guardrail** there |
| `400 bedrock_guardrail_invalid` | No guardrail with that id and version in the connected region. Check them on **AWS account**, or remove the guardrail |
| `finish_reason` is `content_filter` | Your guardrail, or the model's own filter, blocked the prompt or the answer. Review the guardrail's policies in the Amazon Bedrock console |
| "The guardrail wasn't saved" | See [the check messages](controls.md#turn-on-a-guardrail) |

## Contact support

Email **contact@aicloudgateway.com** with your AWS account ID and, for a specific
call, its `x-request-id` header (or the error code and time). Never send your
API key.
