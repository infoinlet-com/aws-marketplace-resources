# Models

[AI Cloud Gateway](README.md) > Models

The gateway routes among the models in its Amazon Bedrock catalog: models from
Amazon, Anthropic, OpenAI, Meta, Mistral, DeepSeek, Qwen, Google, NVIDIA,
Moonshot AI, MiniMax, Z.ai and xAI. They all run in your AWS account. You
choose which ones your routing uses on the dashboard's **Models** page.

[Tiers](#tiers) | [Recommended models](#recommended-models) |
[Choose models](#choose-models) | [Status](#status) | [Test a model](#test-a-model) |
[Pin a model](#pin-a-model) | [New models](#new-models) |
[List your models](#list-your-models) | [The catalog](#the-catalog)

## Tiers

Every model has one tier, set by us. It says what the model is for, not what it
costs. You cannot change a model's tier.

| Tier | For |
|---|---|
| **Light** | Greetings, classification, short extraction |
| **Standard** | Everyday writing, summaries, ordinary code |
| **Advanced** | Proofs, hard code, multi-step reasoning |

The Models page shows one column per tier, with how many of its models are in
routing. *None in routing* means requests of that tier go to models of another
tier. Within the models in routing, the gateway still picks the cheapest one
expected to answer each request well.

## Recommended models

About two models per tier are **recommended**, marked with a star. Until you
choose models, routing uses only these:

`amazon.nova-micro`, `amazon.nova-lite`, `amazon.nova-pro`,
`meta.llama3-3-70b`, `openai.gpt-oss-120b`, `anthropic.claude-haiku-5-5`,
`anthropic.claude-sonnet-5-5`, `anthropic.claude-opus-5-5`.

If you never choose, you follow this set, which we keep current.

## Choose models

1. On **Models**, choose **Choose models**. Each model becomes a switch.
2. Switch models on or off. The provider buttons pick the ready models of whole
   providers. The chips and column counts preview routing as you go.
3. Choose **Save**. It takes effect within a minute.

Once saved, routing uses exactly the models you switched on that your account
can call. **Reset to recommended** clears your choice, so you follow our set
again. A choice that leaves no model the gateway can call is refused.

## Status

Each model shows one status:

| Status | Meaning |
|---|---|
| *In routing* | Switched on, and your account can call it. A tick badge means it passed its last test |
| *Needs access* | Switched on, but your AWS account has no access to it yet. The chip links to the Bedrock console. [Enable access](aws-account.md#enable-more-models) |
| *Off* | Not in your routing |
| *Test failed* | Its last [test](#test-a-model) failed. Hover for the reason |

When you connect your AWS account, the dashboard asks Bedrock which catalog
models your account can use. This spends no tokens. Models Bedrock does not
offer in your connected region are not shown.

## Test a model

**Test** sends one tiny prompt (at most 16 output tokens) through your role, to
the model, the way the router would. A pass marks the model as tested; a
failure says what to fix. AWS bills it as a normal small Bedrock request. It is
not a routed request, so it does not count toward your plan.

## Pin a model

Set `model` to a model id to use one fixed model. See
[How routing works](routing.md#pick-a-mode).

- **Before you choose models**, you can pin any catalog model offered in your
  region, recommended or not. If it fails, fallback moves only to recommended
  models.
- **After you choose models**, you can pin only models you switched on. Any
  other pin gets `403 model_not_permitted`. Fallback stays within your choice.
- A pinned model your account has no access to yet fails with
  `403 bedrock_model_not_enabled`.

## New models

When we add models to the catalog, they arrive **not recommended**, so a catalog
update never changes your routing by itself. If you have chosen models, new ones
show a *New* badge and stay off until you switch them on. The response header
`x-acg-catalog-version` names the catalog used for each request.

## List your models

```bash
curl https://api.aicloudgateway.com/v1/models -H "Authorization: Bearer $ACG_API_KEY"
```

It lists the routing modes (`auto`, `auto:cost`, `auto:balanced`,
`auto:quality`) and the model ids you can use: every catalog model offered in
your region before you choose models, and only your chosen ones after.

## The catalog

Catalog `bedrock-2026-11-23`. Context and maximum output are in tokens.
Recommended models route by default; any other model routes once you switch it
on. *All three* regions means `us-east-1`, `us-east-2` and `us-west-2`. The
**Models** page shows token prices; your AWS bill is the final figure.

<!-- Generated from catalog bedrock-2026-11-23. Do not edit by hand. -->

| Model id | Provider | Tier | Recommended | Context / max output | Supports | Regions |
|---|---|---|---|---|---|---|
| `amazon.nova-lite` | Amazon | Light | Yes | 300K / 10K | tools, images, JSON | all three |
| `amazon.nova-micro` | Amazon | Light | Yes | 128K / 10K | tools, JSON | all three |
| `google.gemma-3-27b` | Google | Light |  | 128K / 8K | images, JSON | all three |
| `mistral.ministral-3-8b` | Mistral | Light |  | 128K / 8K | tools, JSON | all three |
| `nvidia.nemotron-nano-3-30b` | NVIDIA | Light |  | 128K / 8K | tools, JSON | all three |
| `openai.gpt-6-luna` | OpenAI | Light |  | 200K / 32K | tools, JSON | all three |
| `openai.gpt-oss-20b` | OpenAI | Light |  | 128K / 32K | tools, JSON | all three |
| `qwen.qwen3-32b` | Qwen | Light |  | 32K / 8K | tools, JSON | all three |
| `zai.glm-4.7-flash` | Z.ai | Light |  | 128K / 8K | tools, JSON | all three |
| `amazon.nova-pro` | Amazon | Standard | Yes | 300K / 10K | tools, images, JSON | all three |
| `anthropic.claude-haiku-5-5` | Anthropic | Standard | Yes | 200K / 64K | tools, images, JSON | all three |
| `meta.llama3-3-70b` | Meta | Standard | Yes | 128K / 8K | tools, JSON | all three |
| `openai.gpt-oss-120b` | OpenAI | Standard | Yes | 128K / 32K | tools, JSON | `us-east-1`, `us-west-2` |
| `deepseek.v3-2` | DeepSeek | Standard |  | 128K / 8K | tools, JSON | all three |
| `minimax.minimax-m2-5` | MiniMax | Standard |  | 128K / 8K | tools, JSON | all three |
| `mistral.devstral-2` | Mistral | Standard |  | 128K / 8K | tools, JSON | all three |
| `mistral.mistral-large-3` | Mistral | Standard |  | 128K / 8K | tools, images, JSON | all three |
| `moonshotai.kimi-k2-5` | Moonshot AI | Standard |  | 128K / 16K | tools, images, JSON | all three |
| `nvidia.nemotron-super-3-120b` | NVIDIA | Standard |  | 128K / 8K | tools, JSON | all three |
| `openai.gpt-6-1-terra` | OpenAI | Standard |  | 200K / 32K | tools, JSON | all three |
| `qwen.qwen3-next-80b` | Qwen | Standard |  | 128K / 8K | tools, JSON | all three |
| `zai.glm-4.7` | Z.ai | Standard |  | 128K / 8K | tools, JSON | all three |
| `anthropic.claude-opus-5-5` | Anthropic | Advanced | Yes | 200K / 64K | tools, images, JSON | all three |
| `anthropic.claude-sonnet-5-5` | Anthropic | Advanced | Yes | 200K / 64K | tools, images, JSON | all three |
| `anthropic.claude-fable-5-2` | Anthropic | Advanced |  | 200K / 64K | tools, images, JSON | all three |
| `moonshotai.kimi-k3` | Moonshot AI | Advanced |  | 128K / 16K | tools, JSON | all three |
| `openai.gpt-6-2-astra` | OpenAI | Advanced |  | 200K / 32K | tools, JSON | all three |
| `openai.gpt-6-2-sol` | OpenAI | Advanced |  | 200K / 32K | tools, JSON | all three |
| `xai.grok-4-7` | xAI | Advanced |  | 128K / 8K | tools, JSON | all three |
| `zai.glm-5` | Z.ai | Advanced |  | 128K / 8K | tools, JSON | all three |

<!-- End of generated table (30 models). -->
