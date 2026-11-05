# Examples

[AI Cloud Gateway](README.md) > Examples

Each example assumes you finished [Getting started](getting-started.md) and
have your key in `ACG_API_KEY`.

[Clients](#clients) · [Modes](#choose-how-the-model-is-picked) ·
[Which model answered](#see-which-model-answered) · [Streaming](#stream-the-answer) ·
[Tools](#call-tools) · [JSON](#get-json-back) · [Images](#send-an-image) ·
[Tags](#steer-routing-with-tags) · [Errors](#handle-errors) ·
[AgentCore agent](#use-it-from-an-agent-on-amazon-bedrock-agentcore)

---

## Clients

**curl**

```bash
curl https://api.aicloudgateway.com/v1/chat/completions \
  -H "Authorization: Bearer $ACG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "auto", "messages": [{"role": "user", "content": "What is a sports car?"}]}'
```

**Python** (`pip install openai`)

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url="https://api.aicloudgateway.com/v1",
    api_key=os.environ["ACG_API_KEY"],
)
reply = client.chat.completions.create(
    model="auto",
    messages=[{"role": "user", "content": "What is a sports car?"}],
)
print(reply.choices[0].message.content)
```

The Python examples below reuse this `client`.

**JavaScript / TypeScript** (`npm install openai`)

```javascript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://api.aicloudgateway.com/v1",
  apiKey: process.env.ACG_API_KEY,
});
const reply = await client.chat.completions.create({
  model: "auto",
  messages: [{ role: "user", content: "What is a sports car?" }],
});
console.log(reply.choices[0].message.content);
```

**LangChain** (`pip install langchain-openai`)

```python
import os
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    base_url="https://api.aicloudgateway.com/v1",
    api_key=os.environ["ACG_API_KEY"],
    model="auto",
)
print(llm.invoke("What is a sports car?").content)
```

---

## Choose how the model is picked

```python
client.chat.completions.create(model="auto", ...)          # balanced: the default
client.chat.completions.create(model="auto:cost", ...)     # lean toward cheaper models
client.chat.completions.create(model="auto:quality", ...)  # lean toward stronger models
client.chat.completions.create(model="anthropic.claude-sonnet-5-5", ...)  # pin one model
```

List the ids you can pin:

```bash
curl https://api.aicloudgateway.com/v1/models -H "Authorization: Bearer $ACG_API_KEY"
```

When to use which: [How routing works](routing.md#pick-a-mode).

---

## See which model answered

The response's `model` field names it. The response headers also say why:

```python
raw = client.chat.completions.with_raw_response.create(
    model="auto",
    messages=[{"role": "user", "content": "What is a sports car?"}],
)
print(raw.headers.get("x-acg-model"))     # e.g. amazon.nova-micro
print(raw.headers.get("x-acg-strategy"))  # routed or pinned
print(raw.headers.get("x-request-id"))    # quote this to support
reply = raw.parse()
```

With curl, add `-i` to print the headers. Every header:
[Response headers](api-reference.md#response-headers).

---

## Stream the answer

Use streaming for long answers: a non-streamed request must send its first byte
within 60 seconds.

```python
stream = client.chat.completions.create(
    model="auto",
    messages=[{"role": "user", "content": "Explain how a turbocharger works."}],
    stream=True,
    stream_options={"include_usage": True},
)
for chunk in stream:
    if chunk.choices and chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
    if chunk.usage:  # the final chunk, because of include_usage
        print("\n", chunk.usage)
```

---

## Call tools

The model asks for a tool, you run it and send the result back.

```python
import json

tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Current weather for a city",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
    },
}]
messages = [{"role": "user", "content": "What's the weather in Lisbon?"}]

first = client.chat.completions.create(model="auto", messages=messages, tools=tools)
call = first.choices[0].message.tool_calls[0]
args = json.loads(call.function.arguments)

messages.append(first.choices[0].message)
messages.append({
    "role": "tool",
    "tool_call_id": call.id,
    "content": json.dumps({"city": args["city"], "temp_c": 21, "sky": "clear"}),
})

final = client.chat.completions.create(model="auto", messages=messages, tools=tools)
print(final.choices[0].message.content)
```

The second call can be answered by a different model than the first. To keep
one model for the whole exchange, pin it.

---

## Get JSON back

```python
reply = client.chat.completions.create(
    model="auto",
    messages=[{"role": "user", "content": "Name three sports cars with their top speed."}],
    response_format={
        "type": "json_schema",
        "json_schema": {
            "name": "cars",
            "schema": {
                "type": "object",
                "properties": {
                    "cars": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string"},
                                "top_speed_kmh": {"type": "number"},
                            },
                            "required": ["name", "top_speed_kmh"],
                        },
                    },
                },
                "required": ["cars"],
            },
        },
    },
)
print(json.loads(reply.choices[0].message.content))
```

For JSON without a schema, use `response_format={"type": "json_object"}` and ask
for JSON in the prompt.

---

## Send an image

Images must be base64 data URLs (`png`, `jpeg`, `gif` or `webp`). Image URLs over
HTTP are not fetched.

```python
import base64

with open("car.png", "rb") as f:
    data = base64.b64encode(f.read()).decode()

reply = client.chat.completions.create(
    model="auto",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "What car is this?"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{data}"}},
        ],
    }],
)
print(reply.choices[0].message.content)
```

---

## Steer routing with tags

Write a tag in the system prompt or the latest user message. The router reads it
and removes it before the model sees the prompt.

```python
client.chat.completions.create(
    model="auto",
    messages=[
        {"role": "system", "content": "You review pull requests. task:complex effort:medium"},
        {"role": "user", "content": "Is this lock ordering safe? ..."},
    ],
)
```

```python
client.chat.completions.create(
    model="auto",
    messages=[{"role": "user", "content": "task:simple Translate 'good morning' to French."}],
)
```

Tag rules: [How routing works](routing.md#tags).

---

## Handle errors

Errors use the OpenAI error envelope, so the SDKs raise their usual exceptions.
Match on `code`, which is stable:

```python
import openai

try:
    reply = client.chat.completions.create(
        model="auto", messages=[{"role": "user", "content": "Hello"}]
    )
except openai.APIStatusError as e:
    if e.code == "bedrock_not_connected":
        print("Connect your AWS account in the dashboard.")
    elif e.code == "bedrock_throttled":
        print("Bedrock is throttling every model; retry with backoff.")
    else:
        print(e.status_code, e.code, e.message)
```

Every code and its fix: [Errors](api-reference.md#errors).

---

## Use it from an agent on Amazon Bedrock AgentCore

Keep the key in **AgentCore Identity**, not in the agent's code:

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
Deploy with `agentcore configure -e agent.py`, then `agentcore deploy`; remove
it with `agentcore destroy`. The agent can run in any AWS account; its model
calls run in the account you connected.
