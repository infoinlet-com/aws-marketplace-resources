# Getting started

[Data Guard MCP Server](README.md) > Getting started

Five steps, about 15 minutes. You need:

- an AWS account subscribed to this product in AWS Marketplace;
- AWS CLI v2, configured for a Region where Amazon Bedrock AgentCore is
  available (for example `us-east-1`);
- permission to create an IAM role and use `bedrock-agentcore-control` and
  `bedrock-agentcore`.

The fulfillment page (**Continue to Launch** on the listing) shows these steps
with your account ID and image URI filled in. You can also deploy from the
AgentCore console.

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_URI="709825985650.dkr.ecr.us-east-1.amazonaws.com/info-inlet/data-guard-mcp:<version>"   # from the fulfillment page
```

## 1. Create the IAM role

AgentCore assumes this role to pull the image and write logs.

```bash
cat > trustpolicy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "bedrock-agentcore.amazonaws.com" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "aws:SourceAccount": "${ACCOUNT_ID}" },
      "ArnLike": { "aws:SourceArn": "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:*" }
    }
  }]
}
JSON

aws iam create-role --role-name bedrock-agentcore-role \
  --assume-role-policy-document file://trustpolicy.json
```

## 2. Attach permissions

The fulfillment page's policy, minus Bedrock model access: Data Guard never
calls a model.

```bash
cat > permissionspolicy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"],
      "Resource": ["arn:aws:ecr:${AWS_REGION}:709825985650:repository/*"] },
    { "Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["logs:DescribeLogStreams", "logs:CreateLogGroup"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/bedrock-agentcore/runtimes/*"] },
    { "Effect": "Allow", "Action": ["logs:DescribeLogGroups"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:*"] },
    { "Effect": "Allow", "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": ["arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"] },
    { "Effect": "Allow",
      "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"],
      "Resource": ["*"] },
    { "Effect": "Allow", "Action": "cloudwatch:PutMetricData", "Resource": "*",
      "Condition": { "StringEquals": { "cloudwatch:namespace": "bedrock-agentcore" } } },
    { "Effect": "Allow",
      "Action": ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
                 "bedrock-agentcore:GetWorkloadAccessTokenForUserId"],
      "Resource": ["arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:workload-identity-directory/default",
                   "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:workload-identity-directory/default/workload-identity/*"] }
  ]
}
JSON

aws iam put-role-policy --role-name bedrock-agentcore-role \
  --policy-name bedrock-agentcore-permissions \
  --policy-document file://permissionspolicy.json
```

## 3. Create the runtime

```bash
aws bedrock-agentcore-control create-agent-runtime \
  --region "$AWS_REGION" \
  --agent-runtime-name data_guard_mcp \
  --agent-runtime-artifact "{\"containerConfiguration\": {\"containerUri\": \"$IMAGE_URI\"}}" \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/bedrock-agentcore-role" \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --protocol-configuration '{"serverProtocol": "MCP"}'
```

Note `agentRuntimeArn` and `agentRuntimeId` from the output. Optional settings,
such as a default redaction key or an audit log, are environment variables:
add `--environment-variables '{...}'`. See [Configuration](configuration.md).

## 4. Wait for READY

```bash
aws bedrock-agentcore-control get-agent-runtime --region "$AWS_REGION" \
  --agent-runtime-id <agentRuntimeId> --query status --output text
```

## 5. Make your first call

```bash
export PAYLOAD='{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "redact_data", "arguments": {"text": "Call Sarah on 415-555-2671, SSN 123-45-6789"}}}'

aws bedrock-agentcore invoke-agent-runtime --region "$AWS_REGION" \
  --agent-runtime-arn "<agentRuntimeArn>" \
  --content-type application/json \
  --accept "application/json, text/event-stream" \
  --payload "$(echo -n "$PAYLOAD" | base64)" output.json
```

`output.json` holds the result, with
`"text": "Call Sarah on <PHONE_NUMBER>, SSN <US_SSN>"` and a receipt. Use
`"method": "tools/list"` to see all five tools.

## Next

- [Examples](examples.md) - connect from Python or your agent framework, and
  code to copy.
- [Policies and strategies](policies.md) - choose a pack for your regime.
- [Configuration](configuration.md) - redaction key, audit log, health check.
