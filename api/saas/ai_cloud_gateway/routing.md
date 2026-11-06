# How routing works

[AI Cloud Gateway](README.md) > How routing works

## Pick a mode

| `model` | Use it for |
|---|---|
| `auto` (default) | Most work. The cheapest model expected to answer well |
| `auto:cost` | High volume, simple work: classification, extraction, short replies |
| `auto:quality` | Work where a wrong answer costs more than a stronger model |
| a model id, e.g. `anthropic.claude-sonnet-5-5` | One fixed model, e.g. for a whole conversation. `GET /models` lists ids |

With `auto`, the gateway reads the request (task, difficulty, length, tools,
images, and your `max_tokens`) and picks from the models enabled in your AWS
account. A model that reasons before answering needs room for it within
`max_tokens`; [a small cap changes the choice](api-reference.md#output-cap-and-reasoning). The same request
always gets the same choice. The response's `model` field and
[headers](api-reference.md#response-headers) say which model answered.

## Deterministic and explainable

The choice is made by a rules engine, not by another language model:

- **The same request, mode and catalog version always choose the same model.**
  A choice changes only when your request or settings change, or when we
  publish a new model catalog or update the routing rules.
- **It takes milliseconds** and makes no extra model call, so routing adds no
  tokens to your Bedrock bill.
- **You can audit each decision** from the response headers: `x-acg-model` (the
  model that answered), `x-acg-strategy` (`routed` or `pinned`), `x-acg-mode`
  and `x-acg-catalog-version`.

If [fallback](#fallback) moves a request, `x-acg-model` names the model that
answered, not the first choice.

## Fallback

If the chosen model is throttled or unavailable, the gateway moves to the next
suitable one before any output is sent. Requests Bedrock rejects as invalid are
not retried.

## Tags

Add a tag to the system prompt or the latest user message to say how hard the
task is. The gateway removes it before the model sees the prompt.

| Tag | Effect |
|---|---|
| `task:simple` | Allows a cheaper model |
| `task:complex` | Chooses a stronger model |
| `effort:low`, `effort:medium`, `effort:high` | As `task:complex`, and the model reasons at that effort, if it supports reasoning |

[Example](examples.md#steer-routing-with-tags).

Rules:

- Write the tag exactly: no space after the colon (`task:complex`, not
  `task: complex`). Tags inside code blocks are ignored.
- A tag in the user message wins over one in the system prompt.
- Pinned models ignore tags.
- With `effort:high`, an answer can take minutes. Use `stream: true` to show
  output as it arrives.
- If your end users write prompts, they can write tags too, and move requests to
  more expensive models.

## Conversations

The gateway is stateless: send the full `messages` on every call, as with the
OpenAI API. Each turn is routed on its own, so turns can go to different models;
pin a model to keep one.
