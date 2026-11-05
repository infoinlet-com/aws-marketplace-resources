# Getting started

[AI Cloud Gateway](README.md) > Getting started

Five steps, about 15 minutes. You need an AWS account where you can create a
CloudFormation stack with an IAM role. Your requests run in that account.

## 1. Subscribe and claim

1. On the AWS Marketplace listing, choose **View purchase options**, pick a plan
   and term, and subscribe.
2. Choose **Set up your account**, sign in or create an account, and **claim the
   subscription**.

It shows `pending` until AWS confirms the purchase (usually a few minutes), then
`active`. Carry on with the next steps meanwhile.

## 2. Create an API key

On **API keys**, create a key. It starts with `acg_` and is **shown once**, so
store it now.

## 3. Connect your AWS account

1. On **AWS account**, choose **Launch stack in the AWS console** and sign in to
   the AWS account you want to use.
2. Leave the parameters as they are, acknowledge the IAM role, and create the
   stack.
3. At `CREATE_COMPLETE`, copy **RoleArn** from the **Outputs** tab.
4. In the dashboard, paste it, pick a region (`us-east-1`, `us-east-2` or
   `us-west-2`) and choose **Test and save**.

The role can only call and list Bedrock models.
[What it can do](aws-account.md#what-the-stack-creates).

## 4. Enable models, if any are listed

The dashboard lists models your AWS account has not enabled yet. Anthropic
Claude models need a one-time approval by an administrator of your AWS account:
in the Bedrock console's **Model catalog** (same region), open each listed model
and enable it. Then choose **Test again**.

Optional for now: until then, requests go to the models you already have.

## 5. Make your first call

```bash
export ACG_API_KEY="acg_..."

curl https://api.aicloudgateway.com/v1/chat/completions \
  -H "Authorization: Bearer $ACG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "auto", "messages": [{"role": "user", "content": "What is a sports car?"}]}'
```

You get an answer, and `model` names the Bedrock model that gave it, for example
`amazon.nova-micro`.

If you get an error instead:

| `code` | Go back to |
|---|---|
| `api_key_required`, `invalid_api_key` | Step 2 |
| `subscription_inactive` | Step 1: wait for `active` |
| `bedrock_not_connected` | Step 3 |
| `bedrock_model_not_enabled` | Step 4 |

Anything else: [Troubleshooting](troubleshooting.md).

## Next

- [Examples](examples.md) - your language or framework, streaming, tools, JSON.
- [How routing works](routing.md) - choosing between cost and quality.
