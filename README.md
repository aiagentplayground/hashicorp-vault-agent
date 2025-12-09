# HashiCorp Vault MCP Server and Agents with kagent

This guide explains how to deploy the HashiCorp Vault MCP Server on Kubernetes using kmcp and create AI agents that interact with Vault for secret management, policy generation guidance, and PKI operations.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Part 1: Deploy the Vault MCP Server](#part-1-deploy-the-vault-mcp-server)
- [Part 2: Deploy Vault Agents](#part-2-deploy-vault-agents)
- [Part 3: Advanced Agent Capabilities](#part-3-advanced-agent-capabilities)
- [Part 4: Testing the Agents](#part-4-testing-the-agents)
- [Troubleshooting](#troubleshooting)

---

## Overview

This setup consists of the following components:

1. **Vault MCP Server** - A Model Context Protocol server that provides AI models with access to HashiCorp Vault APIs for managing secrets, mounts, and PKI certificates.

2. **Vault Expert Agent** - A full-featured agent that can create, read, update, and delete secrets, manage mounts, and handle PKI operations.

3. **Vault List Agent** - A read-only agent that can only list mounts and secrets (no write or delete operations).

4. **Enhanced Expert Agent** - An expert agent with detailed system instructions for guided secret rotation and policy generation workflows.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        kagent Agent                              │
│  ┌─────────────────────────┐  ┌─────────────────────────────┐   │
│  │         Tools           │  │      System Message         │   │
│  │     (MCP Server)        │  │     (Instructions)          │   │
│  └─────────────────────────┘  └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                │
                ▼
       ┌──────────────────┐     ┌─────────────────┐
       │  Vault MCP       │────▶│  HashiCorp      │
       │  Server          │     │  Vault          │
       └──────────────────┘     └─────────────────┘
```

---

## Prerequisites

Before you begin, ensure you have:

- A Kubernetes cluster (kind, minikube, EKS, GKE, etc.)
- `kubectl` configured to access your cluster
- kagent installed in your cluster ([Quick Start Guide](https://kagent.dev/docs/kagent/getting-started/quickstart))
- kmcp controller installed ([kmcp Installation](https://kagent.dev/docs/kmcp/deploy/install-controller))
- A running HashiCorp Vault instance with:
  - Vault address (e.g., `https://vault.example.com:8200`)
  - Vault token with appropriate permissions
  - (Optional) Vault namespace for Enterprise/HCP Vault

### Install kagent (if not already installed)

```bash
# Add the kagent Helm repository
helm repo add kagent https://kagent-dev.github.io/kagent
helm repo update

# Install kagent CRDs
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace

# Install kagent
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent
```

### Install kmcp controller (if not already installed)

```bash
# Install kmcp CRDs
helm install kmcp-crds oci://ghcr.io/kagent-dev/kmcp/helm/kmcp-crds \
  --namespace kagent

# Install kmcp controller
helm install kmcp oci://ghcr.io/kagent-dev/kmcp/helm/kmcp \
  --namespace kagent
```

---

## Part 1: Deploy the Vault MCP Server

### Step 1: Create Kubernetes Secret for Vault Credentials

Create a secret containing your Vault connection details:

```bash
kubectl apply -f- <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-mcp-credentials
  namespace: kagent
type: Opaque
stringData:
  VAULT_ADDR: "https://vault.example.com:8200"
  VAULT_NAMESPACE: "admin"
  VAULT_TOKEN: "hvs.your-vault-token-here"
EOF
```

> **Security Note**: For production environments, consider using:
> - External Secrets Operator to sync secrets from an external secrets manager
> - Vault Agent Injector for dynamic token rotation
> - Kubernetes service account authentication instead of static tokens

### Step 2: Deploy the MCPServer Resource

Create the Vault MCP Server using the kmcp MCPServer CRD:

```bash
kubectl apply -f- <<EOF
apiVersion: kagent.dev/v1alpha1
kind: MCPServer
metadata:
  name: vault-mcp-server
  namespace: kagent
spec:
  deployment:
    image: hashicorp/vault-mcp-server:latest
    cmd: vault-mcp-server
    args:
      - stdio
    port: 3000
    secretRefs:
      - name: vault-mcp-credentials
  stdioTransport: {}
  transportType: stdio
EOF
```

### Step 3: Verify the MCP Server Deployment

```bash
# Check the MCPServer resource status
kubectl get mcpserver -n kagent vault-mcp-server

# Check the pod is running
kubectl get pods -n kagent -l app.kubernetes.io/name=vault-mcp-server

# View pod logs for any errors
kubectl logs -n kagent -l app.kubernetes.io/name=vault-mcp-server
```

### Step 4: (Optional) Test with MCP Inspector

```bash
# Port-forward the MCP server
kubectl port-forward -n kagent deploy/vault-mcp-server 3000

# In another terminal, run the MCP Inspector
npx @modelcontextprotocol/inspector
```

Connect using:
- **Transport Type**: Streamable HTTP
- **URL**: `http://127.0.0.1:3000/mcp`

---

## Part 2: Deploy Vault Agents

### Agent 1: Vault Expert Agent (Full Access)

This agent has full capabilities to manage secrets, mounts, and PKI certificates.

```bash
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: vault-expert-agent
  namespace: kagent
spec:
  description: A HashiCorp Vault expert agent that helps users manage secrets, mounts, and PKI certificates using the Vault MCP server.
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |-
      You are an expert HashiCorp Vault agent that helps users securely manage secrets, mounts, and PKI certificates.
      
      # Capabilities
      You can help users with:
      - Creating, listing, and deleting secret mounts (KV v1, KV v2)
      - Reading, writing, listing, and deleting secrets in KV mounts
      - Managing PKI secrets engine (enabling, configuring, issuing certificates)
      - Managing PKI roles and certificate issuance
      
      # Instructions
      - If the user question is unclear, ask for clarification before running any tools
      - Always be helpful and friendly
      - When working with secrets, be cautious and confirm destructive operations
      - Explain what each operation does before executing it
      - If you don't know how to answer the question, DO NOT make things up. Respond with "Sorry, I don't know how to answer that" and ask the user to clarify
      - If you are unable to help, refer the user to https://developer.hashicorp.com/vault for more information
      
      # Security Best Practices
      - Never expose secret values in logs or unnecessary outputs
      - Recommend least-privilege access patterns
      - Suggest appropriate secret rotation practices
      - Warn users about potential security implications of their requests
      
      # Response format
      - ALWAYS format your response as Markdown
      - Include a summary of actions taken and explanation of results
      - Format lists in clear, readable tables when appropriate
    tools:
      - type: McpServer
        mcpServer:
          name: vault-mcp-server
          kind: MCPServer
          toolNames:
            - vault_mount_create
            - vault_mount_list
            - vault_mount_delete
            - vault_kv_list
            - vault_kv_read
            - vault_kv_write
            - vault_kv_delete
            - vault_pki_enable
            - vault_pki_configure
            - vault_pki_role_create
            - vault_pki_role_list
            - vault_pki_role_delete
            - vault_pki_issue
EOF
```

### Agent 2: Vault List Agent (Read-Only)

This agent can only list resources - no create, update, or delete operations.

```bash
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: vault-list-agent
  namespace: kagent
spec:
  description: A HashiCorp Vault agent that helps users list secrets and mounts.
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |-
      You are a HashiCorp Vault agent that helps users list secrets and mounts.
      
      # Instructions
      - If the user question is unclear, ask for clarification before running any tools
      - Always be helpful and friendly
      - If you don't know how to answer the question, DO NOT make things up. Respond with "Sorry, I don't know how to answer that" and ask the user to clarify
      
      # Response format
      - ALWAYS format your response as Markdown
      - Format lists in a clear, readable table when appropriate
    tools:
      - type: McpServer
        mcpServer:
          name: vault-mcp-server
          kind: MCPServer
          toolNames:
            - vault_mount_list
            - vault_kv_list
EOF
```

### Verify Agent Deployment

```bash
# Check both agents are created
kubectl get agents -n kagent

# Check agent status
kubectl get agent vault-expert-agent -n kagent -o yaml
kubectl get agent vault-list-agent -n kagent -o yaml
```

---

## Part 3: Advanced Agent Capabilities

The most effective way to give agents advanced capabilities is through detailed instructions in the system message. The agent uses its MCP tools (vault_kv_read, vault_kv_write, etc.) to execute workflow steps based on these instructions.

This section shows how to create an enhanced agent with guided workflows for:
- **Secret rotation** with confirmation and verification
- **Policy generation** with best practices guidance

### Enhanced Expert Agent

Deploy an agent with detailed instructions for rotation and policy generation:

```bash
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: vault-expert-agent-with-skills
  namespace: kagent
spec:
  description: A HashiCorp Vault expert agent with advanced capabilities for secret rotation and policy management.
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |-
      You are an expert HashiCorp Vault agent with advanced capabilities for managing secrets, policies, and automation workflows.
      
      # Capabilities
      You can help users with:
      - Creating, listing, and deleting secret mounts (KV v1, KV v2)
      - Reading, writing, listing, and deleting secrets in KV mounts
      - Managing PKI secrets engine
      - **Rotating secrets** following secure rotation procedures
      - **Generating ACL policies** based on requirements
      
      # Secret Rotation Procedure
      When asked to rotate a secret:
      1. **Read Current Secret**: Use vault_kv_read to get current values
      2. **Generate New Credentials**: 
         - For passwords: Generate 32+ chars with uppercase, lowercase, numbers, symbols
         - For API keys: Suggest format like "key_" followed by 32+ random alphanumeric chars
      3. **Show Rotation Plan**: Display a plan showing:
         - Path being rotated
         - Keys being updated
         - Preview of old value (first 4 chars + ****)
         - Preview of new value (first 4 chars + ****)
      4. **Request Confirmation**: Ask user to confirm before proceeding
      5. **Execute Rotation**: Use vault_kv_write to store new values
      6. **Verify**: Read back the secret to confirm success
      
      # Policy Generation Guidelines
      When asked to create a Vault policy:
      1. **Gather Requirements**:
         - What paths need access?
         - What capabilities are needed? (create, read, update, delete, list, sudo, deny)
         - What's the intended use case?
      2. **Generate HCL Policy**: Format the policy in proper HCL:
         ```
         # Policy: <policy-name>
         path "<path>" {
           capabilities = ["<cap1>", "<cap2>"]
         }
         ```
      3. **Explain Each Rule**: Describe what each path/capability allows
      4. **Recommend Least Privilege**: Suggest the minimum permissions needed
      
      # Valid Capabilities
      - create: Create new data
      - read: Read existing data
      - update: Update existing data
      - delete: Delete data
      - list: List keys/paths (does NOT allow reading values)
      - sudo: Perform privileged operations
      - deny: Explicitly deny access
      
      # Common Policy Patterns
      ## Read-Only Access
      ```
      path "secret/data/myapp/*" {
        capabilities = ["read", "list"]
      }
      path "secret/metadata/myapp/*" {
        capabilities = ["list"]
      }
      ```
      
      ## Application Full Access
      ```
      path "secret/data/myapp/*" {
        capabilities = ["create", "read", "update", "delete", "list"]
      }
      ```
      
      ## CI/CD Pipeline
      ```
      path "secret/data/ci/*" {
        capabilities = ["read", "list"]
      }
      path "auth/token/create" {
        capabilities = ["update"]
      }
      ```
      
      # Instructions
      - Use MCP tools for direct Vault operations
      - Always explain what you're doing before executing
      - Confirm destructive operations with the user
      - For rotation, ALWAYS show a plan and get confirmation first
      - For policies, explain the security implications
      
      # Security Best Practices
      - Never expose full secret values in outputs (show first 4 chars only)
      - Recommend least-privilege access patterns
      - Suggest secret rotation schedules (90 days for passwords, 30 days for API keys)
      - Warn about overly permissive policies
      
      # Response format
      - ALWAYS format your response as Markdown
      - Use code blocks for policies and commands
      - Include summaries of actions and results
    tools:
      - type: McpServer
        mcpServer:
          name: vault-mcp-server
          kind: MCPServer
          toolNames:
            - vault_mount_create
            - vault_mount_list
            - vault_mount_delete
            - vault_kv_list
            - vault_kv_read
            - vault_kv_write
            - vault_kv_delete
            - vault_pki_enable
            - vault_pki_configure
            - vault_pki_role_create
            - vault_pki_role_list
            - vault_pki_role_delete
            - vault_pki_issue
EOF
```

---

## Part 4: Testing the Agents

### Option 1: Using the kagent Dashboard

```bash
kagent dashboard
```

Navigate to your agent and start chatting.

### Option 2: Using the kagent CLI

```bash
# Test the expert agent
kagent invoke --agent vault-expert-agent --task "List all mounts in Vault"

# Test the list agent
kagent invoke --agent vault-list-agent --task "Show me all secret engines"

# Test the enhanced agent's capabilities
kagent invoke --agent vault-expert-agent-with-skills --task "Generate a read-only policy for secret/apps/*"
kagent invoke --agent vault-expert-agent-with-skills --task "Help me rotate the password at secret/myapp/database"
```

---

## Troubleshooting

### MCP Server Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n kagent -l app.kubernetes.io/name=vault-mcp-server

# Check pod logs
kubectl logs -n kagent -l app.kubernetes.io/name=vault-mcp-server

# Verify secret exists
kubectl get secret vault-mcp-credentials -n kagent
```

### Agent Not Finding Tools

If the agent reports it cannot find tools:

1. Verify the MCP server is running and healthy
2. Check that tool names match exactly (use MCP Inspector to discover actual tool names)
3. Try removing the `toolNames` field to expose all tools:

```yaml
tools:
  - type: McpServer
    mcpServer:
      name: vault-mcp-server
      kind: MCPServer
```

### Skills/A2A Config Errors

If you see errors about unknown fields like `spec.skills`, `spec.a2aConfig`, or `spec.declarative.a2aConfig`:

1. **Remove these fields** - They may require a newer version of kagent or Solo Enterprise
2. **Use enhanced system messages** - Embed detailed workflow instructions in `systemMessage` (see Part 3)
3. The core agent functionality works without these fields

The working Agent structure is:
```yaml
spec:
  description: ...
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |-
      ...
    tools:
      - type: McpServer
        mcpServer:
          name: <mcp-server-name>
          kind: MCPServer
```

### Vault Connection Issues

```bash
# Test Vault connectivity from inside the cluster
kubectl run vault-test --rm -it --image=curlimages/curl -- \
  curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  https://vault.example.com:8200/v1/sys/health
```

---

## Agent Comparison

| Feature | Vault List Agent | Vault Expert Agent | Expert + Enhanced Skills |
|---------|------------------|-------------------|--------------------------|
| List mounts | ✅ | ✅ | ✅ |
| List secrets | ✅ | ✅ | ✅ |
| Read secrets | ❌ | ✅ | ✅ |
| Write secrets | ❌ | ✅ | ✅ |
| Delete secrets | ❌ | ✅ | ✅ |
| Create mounts | ❌ | ✅ | ✅ |
| PKI management | ❌ | ✅ | ✅ |
| Secret rotation guidance | ❌ | ❌ | ✅ |
| Policy generation help | ❌ | ❌ | ✅ |
| A2A skill discovery | ✅ | ✅ | ✅ |
| Use case | Audit/Discovery | Administration | Full Automation |

> **Note**: "Secret rotation guidance" and "Policy generation help" are provided through enhanced system message instructions. The agent uses the same MCP tools (vault_kv_read, vault_kv_write) but follows detailed procedures embedded in its instructions.

---

## Security Considerations

1. **Least Privilege**: Use the List Agent for users who only need to discover what exists in Vault.

2. **Token Scoping**: Create dedicated Vault tokens for each agent with only the required permissions.

3. **Network Policies**: Consider implementing Kubernetes NetworkPolicies to restrict which pods can communicate with the MCP server.

4. **Audit Logging**: Enable Vault audit logging to track all operations performed through the agents.

5. **Secret Rotation**: Implement regular rotation of the Vault token stored in the Kubernetes secret.

6. **System Message Review**: Review agent system messages before deployment to ensure rotation and policy generation instructions follow security best practices.

---

## Cleanup

```bash
# Delete agents
kubectl delete agent vault-expert-agent -n kagent
kubectl delete agent vault-list-agent -n kagent
kubectl delete agent vault-expert-agent-with-skills -n kagent

# Delete MCP server
kubectl delete mcpserver vault-mcp-server -n kagent

# Delete secret
kubectl delete secret vault-mcp-credentials -n kagent
```

---

## References

- [kagent Documentation](https://kagent.dev/docs/kagent)
- [kagent Skills Guide](https://kagent.dev/docs/kagent/examples/skills)
- [kmcp Documentation](https://kagent.dev/docs/kmcp)
- [HashiCorp Vault MCP Server](https://developer.hashicorp.com/vault/docs/mcp-server)
- [A2A Protocol](https://a2a.guide)
- [Model Context Protocol](https://modelcontextprotocol.io)
- [Agent Registry](https://github.com/agentregistry-dev/agentregistry)
