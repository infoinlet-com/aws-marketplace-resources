# API reference

[AI Cloud Gateway](README.md) > API reference

[Authentication](#authentication) | [POST /chat/completions](#post-chatcompletions) |
[GET /models](#get-models) | [Response headers](#response-headers) |
[Limits](#limits) | [Errors](#errors)

Base URL: `https://api.aicloudgateway.com/v1`. The API follows the OpenAI Chat
Completions format; fields that do not apply are ignored, not rejected.

## Authentication

```
Authorization: Bearer acg_...
```

Create keys on the dashboard's **API keys** page. A key is shown once and cannot
be recovered, only replaced. You can hold several, for example one per app.

**Rotate without downtime:** create a new key, deploy it, then revoke the old
one. A revoked key stops working within 60 seconds.

## POST /chat/completions

| Field | Type | Notes |
|---|---|---|
| `model` | string | `auto` (default), `auto:cost`, `auto:quality`, or a model id. See [routing](routing.md) |
| `messages` | object[] | Required. Roles: `system`, `developer`, `user`, `assistant`, `tool` |
| `max_tokens` / `max_completion_tokens` | integer | Output cap |
| `temperature` | number | 0 to 2. Ignored while the model reasons (`effort:` tags) |
| `top_p` | number | 0 to 1. Ignored while the model reasons |
| `stop` | string or string[] | Stop sequences |
| `stream` | boolean | Server-sent events |
| `stream_options.include_usage` | boolean | Adds a final chunk with token usage |
| `tools` | object[] | Function tools with a JSON Schema `parameters` |
| `tool_choice` | string or object | `none`, `auto`, `required`, or `{"type": "function", "function": {"name": ...}}` |
| `response_format` | object | `{"type": "json_object"}` or `{"type": "json_schema", "json_schema": {"name": ..., "schema": {...}}}` |
| `n` | integer | Only `1` |

Message `content` is a string or a list of parts: `{"type": "text", ...}` and
`{"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}`.
Images must be base64 data URLs (`png`, `jpeg`, `gif`, `webp`); web URLs are not
fetched.

**Response:**

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

`model` is the model that answered. `finish_reason` is `stop`, `length`,
`tool_calls` or `content_filter`. Tool calls are in `message.tool_calls`.

`content_filter` means the model's own content filter or your
[guardrail](controls.md#guardrails) stopped the answer. The status is still
`200`. When a guardrail blocks, `content` holds its blocked message.

**Streaming** returns `chat.completion.chunk` events ending with `data: [DONE]`.
If Bedrock fails mid-stream, one event carries the [error](#errors), then
`[DONE]`.

## GET /models

Lists the routing modes and every model id available in your connected region.

```bash
curl https://api.aicloudgateway.com/v1/models -H "Authorization: Bearer $ACG_API_KEY"
```

## Response headers

| Header | Meaning |
|---|---|
| `x-request-id` | Request id. Quote it to support |
| `x-acg-model` | The model that answered |
| `x-acg-strategy` | `routed` (gateway chose) or `pinned` (you named the model) |
| `x-acg-mode` | `cost`, `balanced` or `quality` |
| `x-acg-catalog-version` | Model catalog version used for the choice |
| `x-acg-directives` | Tags applied, if any |
| `x-acg-effort` | Reasoning effort applied, if any |

## Limits

| Limit | Value |
|---|---|
| Time to first byte, and between bytes | 60 seconds. Stream long answers |
| Longest streaming request | 15 minutes |
| Non-streaming request with reasoning | Output up to 21,333 tokens; stream for more |
| Key and subscription changes | Apply within 60 seconds |
| Budget and guardrail changes | Apply within about a minute |
| Regions | `us-east-1`, `us-east-2`, `us-west-2` |

## Errors

OpenAI error envelope, so SDKs raise their usual exceptions. Match on `code`.

```json
{"error": {"message": "Connect your AWS account in the dashboard before calling the API.",
           "type": "permission_error", "param": null, "code": "bedrock_not_connected"}}
```

| Status | `code` | Fix |
|---|---|---|
| 400 | `invalid_request` | Fix the field named in `param` |
| 400 | `invalid_model` | Use `auto`, `auto:cost`, `auto:balanced` or `auto:quality` |
| 400 | `unsupported_parameter` | Set `n` to 1 |
| 400 | `empty_conversation` | Send at least one user or assistant message with content |
| 400 | `unsupported_image_url` | Send images as base64 data URLs (png, jpeg, gif, webp) |
| 400 | `invalid_image` | Fix the base64 image data |
| 400 | `invalid_tool_arguments` | Send tool-call `arguments` as valid JSON |
| 400 | `missing_tool_call_id` | Add `tool_call_id` to each `tool` message |
| 400 | `no_eligible_model` | Input too long, or needs images or tools no enabled model has. Trim it or enable more models |
| 400 | `bedrock_validation_error` | Bedrock rejected the request; the message says why |
| 400 | `bedrock_guardrail_invalid` | Bedrock cannot use the guardrail's id or version. [Fix or remove it](troubleshooting.md#budgets-and-guardrails) |
| 401 | `api_key_required` | Send `Authorization: Bearer acg_...` |
| 401 | `invalid_api_key` | Key wrong or revoked. Create a new one |
| 403 | `subscription_inactive` | Subscription pending, cancelled or expired. Check **Subscriptions** |
| 403 | `bedrock_not_connected` | [Connect your AWS account](getting-started.md#3-connect-your-aws-account) |
| 403 | `bedrock_model_not_enabled` | [Enable the named models](aws-account.md#enable-more-models) |
| 403 | `bedrock_access_denied` | The role was deleted or changed, or the region does not offer the models |
| 403 | `model_not_permitted` | The pinned model is not allowed for your account |
| 403 | `budget_exceeded` | A monthly [budget](controls.md#budgets) is reached. Raise it, or wait for the reset the message names. Not retried by SDKs |
| 403 | `bedrock_guardrail_denied` | Your role may not apply the guardrail. [Update your stack](aws-account.md#update-your-stack) or remove the guardrail |
| 404 | `model_not_found` | Use an id from `GET /models` |
| 429 | `bedrock_throttled` | Retry with backoff, or raise your Bedrock quotas |
| 500 | `internal_error` | Retry. Contact support if it persists |
| 502 | `bedrock_error` | Retry |
