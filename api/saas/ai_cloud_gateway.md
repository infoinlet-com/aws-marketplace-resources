# AI Cloud Gateway (SaaS) - Usage Guide

This guide explains how to subscribe to and use **AI Cloud Gateway**, an LLM
router sold as a SaaS subscription in AWS Marketplace. It picks a suitable
Amazon Bedrock model for each request and runs the request **in your own AWS
account** through a role you create with one CloudFormation stack.

- Base URL: `https://api.aicloudgateway.com/v1`
- Authentication: API key, `Authorization: Bearer acg_...`
- Endpoints: `POST /chat/completions`, `GET /models`
- Clients: existing SDKs and agent frameworks work by changing the base URL and
  the key (section 5).
- Inference: Amazon Bedrock in your AWS account. **Bedrock token usage is billed
  by AWS to your own AWS account.** AI Cloud Gateway bills only for routing.
- Dashboard: `https://dashboard.aicloudgateway.com`

---

## 1. What this product does

Every request names a model, or lets the gateway choose one:

- `model: "auto"` - the gateway reads the request (task type, difficulty, size,
  tools, images, context length) and picks the cheapest model in its catalog
  that is expected to answer it well.
- `model: "auto:cost"`, `"auto:balanced"`, `"auto:quality"` - the same, with a
  stronger lean toward price or toward quality. `auto` is `auto:balanced`.
- `model: "<catalog id>"` - pin one model, for example
  `anthropic.claude-sonnet-5-5`. `GET /models` lists the ids available to you.

The gateway then calls Amazon Bedrock with temporary credentials for the role in
your account. If a model is throttled, unavailable, or not enabled in your
account, it moves to the next suitable model before any output is sent. It never
retries a request that Bedrock rejected as invalid.

Decisions are deterministic: the same request, catalog version and settings give
the same model. Response headers say which model answered and why (section 5.3).

---

## 2. Prerequisites

- An AWS account and an active subscription to **AI Cloud Gateway** in AWS
  Marketplace.
- An AWS account whose Amazon Bedrock you want requests to run in. It can be the
  account that subscribed or any other account you control. You need permission
  to create a CloudFormation stack with an IAM role in it.
- **Model access enabled in Amazon Bedrock** in that account, in the region you
  connect, for the models you want used. A model without access is skipped.
- Supported regions for the connection: `us-east-1`, `us-east-2`, `us-west-2`.
- An HTTP client or any OpenAI-format SDK.

---

## 3. Subscribe and set up your account

1. On the product's AWS Marketplace page, choose **View purchase options**, pick
   a contract term, and subscribe.
2. Choose **Set up your account**. AWS sends you to AI Cloud Gateway and you land
   on `https://dashboard.aicloudgateway.com/marketplace/aws/`.
3. **Sign in**, or **create an account** with your email address.
4. **Claim the subscription.** It is attached to the account you are signed in
   with. A subscription can be claimed by one dashboard account only.
5. Wait for activation. The subscription shows as `pending` until AWS confirms
   the purchase, then `active`. This usually takes a few minutes.
6. Create an API key on the **API keys** page (section 4). Then connect your AWS
   account on the **AWS account** page (section 6). Calls fail with
   `403 bedrock_not_connected` until you do.

The dashboard pages:

| Page | What it shows |
|---|---|
| Overview | Setup checklist and current state |
| Subscriptions | Your subscriptions and their status (`pending`, `active`, `suspended`, `unsubscribed`) |
| AWS account | Connect the AWS account whose Bedrock runs your requests |
| Usage | Routed requests and tokens per day and per model, and this month's included allowance |
| API keys | Create and revoke keys |

---

## 4. API keys

### 4.1 Create a key

**API keys** -> create a key and give it a name. The key starts with `acg_` and
is **shown once**. Copy it into a secret manager straight away. Only a hash of
the key is stored, so a lost key cannot be recovered, only replaced.

Keys belong to your dashboard account, not to one subscription. You can hold
several active keys at once, for example one per application.

### 4.2 Rotate a key

1. Create a new key.
2. Deploy it to your applications.
3. Revoke the old key on the **API keys** page.

A revoked key stops working within 60 seconds and then returns
`401 invalid_api_key`. Because you create the new key before revoking the old
one, rotation needs no downtime.

### 4.3 Send the key

```
Authorization: Bearer acg_...
```

The `Bearer` scheme is required. A request without it returns
`401 api_key_required`.

---

## 5. Call the API

### 5.1 First call

```bash
export ACG_API_KEY="acg_..."

curl https://api.aicloudgateway.com/v1/chat/completions \
  -H "Authorization: Bearer $ACG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "auto", "messages": [{"role": "user", "content": "What is a sports car?"}]}'
```

### 5.2 With the OpenAI Python SDK

```python
from openai import OpenAI

client = OpenAI(base_url="https://api.aicloudgateway.com/v1", api_key="acg_...")
reply = client.chat.completions.create(
    model="auto",  # or auto:cost, auto:quality, or a catalog id
    messages=[{"role": "user", "content": "What is a sports car?"}],
)
print(reply.model)  # the model that answered
print(reply.choices[0].message.content)
```

Any client that lets you set the base URL works the same way.

### 5.3 Response headers

Every successful completion carries these headers:

| Header | Meaning |
|---|---|
| `x-request-id` | The completion id (`chatcmpl-...`). Quote it to support |
| `x-acg-model` | The catalog id of the model that answered |
| `x-acg-strategy` | `routed` (the gateway chose) or `pinned` (you named the model) |
| `x-acg-mode` | `cost`, `balanced` or `quality` |
| `x-acg-catalog-version` | The model catalog the decision used |
| `x-acg-directives` | The `task:` and `effort:` tags that were applied (section 7), when any |
| `x-acg-effort` | The effort the answering model actually applied, when it applied one |

---

## 6. Connect your AWS account

AI Cloud Gateway calls Bedrock as an IAM role in your account. You create that
role with a CloudFormation stack, and it can only be assumed with an External ID
unique to your subscription.

1. In the dashboard, open **AWS account**. Each subscription shows its
   **External ID** and a **Launch stack in the AWS console** link.
2. Sign in to the AWS account whose Bedrock you want to use, then follow the
   link. It opens CloudFormation quick-create with the `ExternalId` parameter
   already filled in. Do not change `ExternalId` or `RouterPrincipalArn`.
3. Acknowledge that the stack creates an IAM role, and create the stack.
4. Wait for `CREATE_COMPLETE`, then copy the `RoleArn` value from the stack's
   **Outputs** tab. It looks like
   `arn:aws:iam::123456789012:role/AICloudGatewayRouter`.
5. Back in the dashboard, paste the Role ARN, pick the region (`us-east-1`,
   `us-east-2` or `us-west-2`), and choose **Test and save**.
6. The check assumes the role exactly as the router does and lists the Bedrock
   text models in that region. On success the page shows the connected account
   and how many models are available.
7. In the Bedrock console of that account and region, make sure **model access**
   is enabled for the models you want requests routed to.

What the stack creates: one IAM role, `AICloudGatewayRouter`, with a maximum
session of one hour. It trusts only the AI Cloud Gateway router role, and only
with your External ID. Its permissions are limited to:

- `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on
  foundation models and on inference profiles in your account;
- `bedrock:ListFoundationModels`, `bedrock:GetFoundationModel`,
  `bedrock:ListInferenceProfiles` and `bedrock:GetInferenceProfile`.

It cannot read or change anything else in your account. To disconnect, delete
the stack; calls then fail with `403 bedrock_access_denied`.

If **Test and save** fails:

| Message | Fix |
|---|---|
| "We couldn't assume this role" | The stack has not finished, the Role ARN was mistyped, or the stack was created with a different External ID. Relaunch from the dashboard link |
| "The role works, but it can't list Amazon Bedrock models" | The role's policy was changed, or Bedrock is not available to your account in that region |
| "This role is in AI Cloud Gateway's AWS account" | Use a role in your own AWS account |

A failed re-check leaves an existing working connection in place.

---

## 7. Steer routing with task and effort tags

You can tell the router how big a task is by writing a tag anywhere in the
system prompt or the latest user message. The router reads the tag and
**removes it before the prompt reaches the model**.

| Tag | Effect |
|---|---|
| `task:complex` | Raises the difficulty score (+0.20, and at least 0.50), so a stronger model is chosen |
| `task:simple` | Lowers the difficulty score (-0.20), so a cheaper model can qualify |
| `task:complex effort:low` / `effort:medium` / `effort:high` | As `task:complex`, and the chosen model reasons (thinks) at that effort, where the model supports it |
| `effort:high` on its own | Implies `task:complex` |

```python
client.chat.completions.create(
    model="auto",
    messages=[
        {"role": "system", "content": "You review pull requests. task:complex effort:medium"},
        {"role": "user", "content": "Is this lock ordering safe? ..."},
    ],
)
```

Rules:

- A tag is a bare token: lower or upper case, no space around the colon, a known
  value, and nothing touching it. `task: complex`, `task:hard`,
  `subtask:complex` and `https://x/task:simple` are not tags and are left in the
  text.
- Tags inside fenced code blocks are neither read nor removed.
- A tag in the user message wins over one in the system prompt, and the last
  value of a key wins.
- `effort` together with `task:simple` is ignored.
- A pinned model ignores tags.
- Effort is applied only by models that support reasoning, and is skipped for a
  call that forces tool use (`tool_choice: "required"` or a named tool) or that
  carries a tool result. `x-acg-effort` tells you when it was applied.
- With `effort:high`, prefer `stream: true`: a long non-streamed answer can hit
  the 60-second time-to-first-byte limit (section 9).

If your end users type the prompts, remember that they can type tags too and
move your requests to stronger, more expensive models.

---

## 8. Endpoint reference

### 8.1 POST /chat/completions

The request follows the OpenAI Chat Completions format, so the OpenAI SDKs and
frameworks built on them work unchanged. AI Cloud Gateway is not affiliated with
OpenAI. Parameters that do not apply are
ignored rather than rejected, because SDKs send some of them by default.

| Field | Type | Default | Notes |
|---|---|---|---|
| `model` | string | `auto` | `auto`, `auto:cost`, `auto:balanced`, `auto:quality`, or a catalog id |
| `messages` | object[] | - | required, at least one. Roles: `system`, `developer`, `user`, `assistant`, `tool` |
| `max_tokens` / `max_completion_tokens` | integer | model's | output cap, at least 1 |
| `temperature` | number | model's | 0 to 2. Dropped when the model is thinking (section 7) |
| `top_p` | number | model's | 0 to 1. Dropped when the model is thinking |
| `stop` | string or string[] | - | stop sequences |
| `n` | integer | `1` | only `1` is supported |
| `stream` | boolean | `false` | server-sent events |
| `stream_options.include_usage` | boolean | `false` | adds a final chunk with token usage |
| `tools` | object[] | - | `type: "function"` tools with a JSON Schema `parameters` |
| `tool_choice` | string or object | - | `none`, `auto`, `required`, or `{"type": "function", "function": {"name": ...}}` |
| `response_format` | object | - | `{"type": "text"}`, `{"type": "json_object"}`, or `{"type": "json_schema", "json_schema": {"name": ..., "schema": {...}}}` |
| `user` | string | - | accepted and ignored |

Message content is a string, or a list of parts:

- `{"type": "text", "text": "..."}`
- `{"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}` -
  images must be base64 data URLs in `png`, `jpeg`, `gif` or `webp`. Image URLs
  over HTTP are not fetched.

Tool calls follow the OpenAI shape: an assistant message carries `tool_calls`,
and you answer each with a `tool` message carrying its `tool_call_id`.

`response_format` of `json_object` or `json_schema` instructs the model to return
a single JSON value, conforming to the schema when one is given.

**Response (non-streaming):**

```json
{
  "id": "chatcmpl-6f1c...",
  "object": "chat.completion",
  "created": 1760400000,
  "model": "amazon.nova-micro",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "A sports car is ..."},
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 14, "completion_tokens": 52, "total_tokens": 66}
}
```

`model` is the catalog id of the model that answered. `finish_reason` is `stop`,
`length`, `tool_calls` or `content_filter`. When the model calls tools,
`message.tool_calls` holds them and `content` may be `null`.

**Response (streaming):** `Content-Type: text/event-stream`, a sequence of
`data: {...}` lines with `object: "chat.completion.chunk"`, ending with
`data: [DONE]`. If Bedrock fails after the stream has started, the stream sends
one `data:` event with the error envelope (section 10) and then `data: [DONE]`.
The model is committed once the first byte is sent, so there is no fallback
after that point.

### 8.2 GET /models

The routing aliases, then every catalog model allowed in your connected region.

```bash
curl https://api.aicloudgateway.com/v1/models -H "Authorization: Bearer $ACG_API_KEY"
```

```json
{"object": "list", "data": [
  {"id": "auto", "object": "model", "created": 1760400000, "owned_by": "aicloudgateway"},
  {"id": "auto:quality", "object": "model", "created": 1760400000, "owned_by": "aicloudgateway"},
  {"id": "anthropic.claude-sonnet-5-5", "object": "model", "created": 1760400000, "owned_by": "aicloudgateway"}
]}
```

The list is abridged above. It needs a connected AWS account, like every other
call.

---

## 9. Limits and behavior

| Limit | Value |
|---|---|
| Time to first byte, and between bytes | 60 seconds. Use `stream: true` for long answers or `effort:high` |
| Longest request, streaming | 15 minutes |
| Non-streaming request with thinking | output budget capped at 21,333 tokens; larger budgets need streaming |
| Key and subscription changes | take effect within 60 seconds |
| `n` | 1 |

- The router is stateless. Every call carries the full `messages`, as in the
  OpenAI API. Trimming a long conversation is the caller's job.
- If no model allowed in your region can hold the input plus the expected output,
  the call fails with `400 no_eligible_model`.
- Turns of one conversation can be answered by different models. To keep one
  model for a whole conversation, pin it.
- Bedrock quotas are your account's. Throttling on one model moves the request to
  the next; if all are throttled you get `429 bedrock_throttled`.

---

## 10. Errors

Errors use the OpenAI error envelope, so OpenAI SDKs raise their usual
exceptions. `code` is a stable identifier you can match on.

```json
{"error": {"message": "Connect your AWS account in the dashboard before calling the API.",
           "type": "permission_error", "param": null, "code": "bedrock_not_connected"}}
```

| Status | `code` | Meaning and fix |
|---|---|---|
| 400 | `invalid_request` | The body failed validation. `param` names the field |
| 400 | `invalid_model` | Unknown routing mode after `auto:`. Use `auto`, `auto:cost`, `auto:balanced` or `auto:quality` |
| 400 | `unsupported_parameter` | `n` other than 1 |
| 400 | `empty_conversation` | No user or assistant content |
| 400 | `unsupported_image_url` | Image was not a base64 data URL in png, jpeg, gif or webp |
| 400 | `invalid_image` | Image data is not valid base64 |
| 400 | `invalid_tool_arguments` | A tool call's `arguments` is not valid JSON |
| 400 | `missing_tool_call_id` | A `tool` message has no `tool_call_id` |
| 400 | `no_eligible_model` | No model allowed in your region can serve this request (for example, the input is too long, or it needs images or tools no allowed model supports) |
| 400 | `bedrock_validation_error` | Bedrock rejected the request as invalid. The message is Bedrock's. Not retried on another model |
| 401 | `api_key_required` | No `Authorization: Bearer ...` header |
| 401 | `invalid_api_key` | The key is wrong, or was revoked |
| 403 | `subscription_inactive` | Your dashboard account has no active subscription: it is still `pending`, it was cancelled or it expired. Check **Subscriptions** in the dashboard and your agreement in AWS Marketplace |
| 403 | `bedrock_not_connected` | Your subscription is active but no AWS account is connected. Complete section 6 |
| 403 | `bedrock_access_denied` | Your AWS account could not run any of the candidate models: model access is not enabled in Bedrock, or the role was deleted or changed |
| 403 | `model_not_permitted` | The pinned model is not allowed for your account |
| 403 | `direct_access_forbidden` | The request reached the gateway without passing through `api.aicloudgateway.com`. Call `https://api.aicloudgateway.com/v1` |
| 404 | `model_not_found` | The pinned model id is not in the catalog. `GET /models` lists valid ids |
| 429 | `bedrock_throttled` | Amazon Bedrock is throttling your account on every candidate model. Retry with backoff, or raise your Bedrock quotas |
| 500 | `internal_error` | An unexpected error in the gateway. Retry; contact support with the time if it persists |
| 502 | `bedrock_error` | Bedrock failed in a way the request cannot fix. Retry |

---

## 11. Use it from an agent on Amazon Bedrock AgentCore

Any agent framework that speaks the OpenAI format can use the gateway as its
model. On AgentCore Runtime, keep the key in **AgentCore Identity** rather than
in the agent's code or environment:

```bash
aws bedrock-agentcore-control create-api-key-credential-provider \
  --name ai-cloud-gateway --api-key acg_... --region us-east-1
```

A Strands agent then reads the key at invocation time:

```python
from bedrock_agentcore.identity.auth import requires_api_key
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent
from strands.models.openai import OpenAIModel

app = BedrockAgentCoreApp()

@requires_api_key(provider_name="ai-cloud-gateway")
def build_agent(*, api_key: str = "") -> Agent:
    model = OpenAIModel(
        client_args={"api_key": api_key, "base_url": "https://api.aicloudgateway.com/v1"},
        model_id="auto",
        params={"max_tokens": 1024},
    )
    return Agent(model=model, system_prompt="You are a support engineer. task:complex")

@app.entrypoint
def invoke(payload: dict) -> dict:
    return {"answer": str(build_agent()(payload.get("prompt", "")))}

if __name__ == "__main__":
    app.run()
```

Requirements: `bedrock-agentcore==1.24.1` and `strands-agents[openai]==1.61.1`.
Deploy with the AgentCore starter toolkit (`agentcore configure -e agent.py`,
then `agentcore deploy`). The agent can run in any AWS account; its model calls
run in the account connected to the key's subscription. Remove the runtime with
`agentcore destroy` when you are done.

---

## 12. Billing

AI Cloud Gateway is a contract (monthly or annual) plus usage, billed through AWS
Marketplace. Current prices are on the listing page.

<!-- TO CONFIRM before publishing: 25,000 = INCLUDED_REQUESTS_PER_MONTH in aicloudgateway-webapp. -->
- **The contract fee includes 25,000 routed requests per calendar month**, per
  subscription. The month runs in UTC and resets at 00:00 UTC on the first.
  Unused requests do not carry over. The **Usage** page shows this month's
  count against the allowance.
- **Beyond the allowance, routed requests are billed per 1,000** (the
  `requests_1k` dimension). Only whole thousands are billed; a remainder is
  carried forward and billed once later traffic completes the thousand.
- A routed request is a call to `POST /chat/completions` that a model answered.
  Calls refused before a model answers (`400`, `401`, `403`, `404`, and calls
  where every candidate model failed) are not counted. `GET /models` is not
  counted.
- **Amazon Bedrock usage is billed by AWS to the AWS account you connected**, at
  your Bedrock prices, and appears under Amazon Bedrock in that account's bill.
  AI Cloud Gateway never runs your requests on its own Bedrock account and does
  not resell tokens.
- Usage is reported to AWS Marketplace every hour. Billed usage appears in the
  AWS Billing console of the subscribing account.

A contract cannot be cancelled mid-term from the console. Turn off auto-renewal
to stop further billing, and see the refund policy on the listing. After a
subscription ends, calls return `403 subscription_inactive`.

---

## 13. Data handling

- **Prompts and completions are never stored.** They pass through the gateway in
  memory, in AWS `us-east-1`, on their way to and from Bedrock in your account.
  They are never written to a log, a database or a file.
- **What is kept:** usage counts (requests, input tokens and output tokens per
  model per hour) and routing decision features (for example the detected task
  type, the difficulty score, the candidate models and their estimated cost,
  the model chosen, and any fallbacks). These power the **Usage** page, billing
  and routing improvements, and contain no prompt or response text.
- API keys are stored only as a SHA-256 hash.
- The gateway holds no long-lived credential for your account. It uses STS
  temporary credentials for your role, which require your External ID.
- If your data must not leave a specific geography outside the US, note the
  `us-east-1` pass-through above before using the service.

---

## 14. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Setup page shows an error after **Set up your account** | Start again from **Set up your account** in the AWS Marketplace console |
| Claim fails: the subscription is linked to another account | The subscription was already claimed by a different dashboard account. Sign in with that account, or contact support |
| Subscription stays `pending` | AWS has not yet confirmed the purchase. Wait a few minutes and reload. If it stays pending for over an hour, contact support with your AWS account ID |
| `403 bedrock_not_connected` | Connect your AWS account (section 6) |
| `403 bedrock_access_denied` | Enable model access in the Bedrock console for the connected region, and check the `AICloudGatewayRouter` stack still exists |
| `403 subscription_inactive` | The subscription is pending, cancelled or expired. Check **Subscriptions** |
| `401 invalid_api_key` | The key was revoked or mistyped. Create a new one on **API keys** |
| `400 no_eligible_model` | The input is too long for every allowed model, or needs a capability none has. Trim the conversation |
| Request times out before any output | Use `stream: true`, especially with `effort:high` |
| `x-acg-directives` missing although you wrote a tag | The tag was malformed (a space after the colon, an unknown value) or inside a code block, or the model was pinned |
| `429 bedrock_throttled` | Your Bedrock quotas in the connected region are exhausted. Retry with backoff or request a quota increase |

---

## 15. Support

Email **contact@infoinlet.com**. We reply within one business day, Monday to
Friday.

Include your AWS account ID, and for a question about a specific call, the
`x-request-id` header value (or the error code and time). Never include your API
key or prompt content you do not want to share.

Billing, cancellation and refunds run through AWS Marketplace; see the refund
policy on the listing.
