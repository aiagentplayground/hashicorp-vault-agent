# HashiCorp Vault MCP Server and Agents with kagent

This guide explains how to deploy the HashiCorp Vault MCP Server on Kubernetes using kmcp, and create AI agents that interact with Vault using kagent.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Part 1: Deploy the Vault MCP Server](#part-1-deploy-the-vault-mcp-server)
- [Part 2: Deploy Vault Agents](#part-2-deploy-vault-agents)
- [Part 3: Testing the Agents](#part-3-testing-the-agents)
- [Troubleshooting](#troubleshooting)

---

## Overview

This setup consists of three main components:

1. **Vault MCP Server** - A Model Context Protocol server that provides AI models with access to HashiCorp Vault APIs for managing secrets, mounts, and PKI certificates.

2. **Vault Expert Agent** - A full-featured agent that can create, read, update, and delete secrets, manage mounts, and handle PKI operations.

3. **Vault List Agent** - A read-only agent that can only list mounts and secrets (no write or delete operations).

### Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  kagent Agent   │────▶│  Vault MCP       │────▶│  HashiCorp      │
│  (Expert/List)  │     │  Server          │     │  Vault          │
└─────────────────┘     └──────────────────┘     └─────────────────┘
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
  VAULT_ADDR: "https://vault.example.com:8200"    # Replace with your Vault address
  VAULT_NAMESPACE: "admin"                         # Replace with your namespace (or leave empty string for OSS Vault)
  VAULT_TOKEN: "hvs.your-vault-token-here"        # Replace with your Vault token
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

You can use the MCP Inspector to verify the Vault MCP Server is working correctly:

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
    a2aConfig:
      skills:
        - id: secrets-management-skill
          name: Secrets Management
          description: Create, read, update, and delete secrets in HashiCorp Vault KV mounts
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - secrets
            - kv
            - security
          examples:
            - "Store my database password securely in Vault"
            - "Read the API key from secret/myapp/config"
            - "List all secrets under the apps/ path"
            - "Delete the old secret at secret/legacy/credentials"
            - "Create a new KV mount called 'team-secrets'"
        - id: mount-management-skill
          name: Mount Management
          description: Create, list, and manage secret mounts in Vault
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - mounts
            - configuration
          examples:
            - "List all mounts in Vault"
            - "Create a new KV v2 mount named 'production-secrets'"
            - "Delete the unused mount at 'old-secrets/'"
        - id: pki-management-skill
          name: PKI Certificate Management
          description: Manage PKI secrets engine, roles, and issue certificates
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - pki
            - certificates
            - tls
          examples:
            - "Enable and configure a PKI secrets engine"
            - "Create a PKI role for issuing certificates"
            - "Issue a certificate for my-service.example.com"
            - "List all PKI roles in the pki/ mount"
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
    a2aConfig:
      skills:
        - id: list-vault-resources
          name: List Vault Resources
          description: List mounts and secrets in HashiCorp Vault
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - list
            - secrets
          examples:
            - "List all mounts in Vault"
            - "List all secrets under the apps/ path"
            - "Show me what's in the secret/data/myapp path"
            - "What secret engines are enabled?"
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

## Part 3: Testing the Agents

### Option 1: Using the kagent Dashboard

```bash
# Launch the kagent dashboard
kagent dashboard
```

Navigate to your agent and start chatting.

### Option 2: Using the kagent CLI

```bash
# Test the expert agent
kagent invoke --agent vault-expert-agent --task "List all mounts in Vault"

# Test the list agent
kagent invoke --agent vault-list-agent --task "Show me all secret engines"
```

### Option 3: Using the A2A Protocol

The agents are exposed via the A2A (Agent-to-Agent) protocol:

```bash
# Port-forward the kagent controller
kubectl port-forward svc/kagent-controller 8083:8083 -n kagent

# Get the agent card for the expert agent
curl localhost:8083/api/a2a/kagent/vault-expert-agent/.well-known/agent.json

# Get the agent card for the list agent
curl localhost:8083/api/a2a/kagent/vault-list-agent/.well-known/agent.json
```

### Option 4: Using the A2A Host CLI

```bash
# Clone the A2A samples repository
git clone https://github.com/a2aproject/a2a-samples.git
cd a2a-samples/samples/python/hosts/cli

# Connect to the vault expert agent
uv run . --agent http://127.0.0.1:8083/api/a2a/kagent/vault-expert-agent

# Or connect to the list agent
uv run . --agent http://127.0.0.1:8083/api/a2a/kagent/vault-list-agent
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
      # Remove toolNames to expose all tools
```

### Vault Connection Issues

```bash
# Test Vault connectivity from inside the cluster
kubectl run vault-test --rm -it --image=curlimages/curl -- \
  curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  https://vault.example.com:8200/v1/sys/health
```

### Common Error Messages

| Error | Solution |
|-------|----------|
| `permission denied` | Check Vault token has required permissions |
| `connection refused` | Verify VAULT_ADDR is correct and accessible from the cluster |
| `namespace not found` | Ensure VAULT_NAMESPACE is correct (or empty for OSS Vault) |
| `tool not found` | Use MCP Inspector to verify actual tool names |

---

## Agent Comparison

| Feature | Vault Expert Agent | Vault List Agent |
|---------|-------------------|------------------|
| List mounts | ✅ | ✅ |
| List secrets | ✅ | ✅ |
| Read secrets | ✅ | ❌ |
| Write secrets | ✅ | ❌ |
| Delete secrets | ✅ | ❌ |
| Create mounts | ✅ | ❌ |
| Delete mounts | ✅ | ❌ |
| PKI management | ✅ | ❌ |
| Use case | Full administration | Audit/Discovery |

---

## Security Considerations

1. **Least Privilege**: Use the List Agent for users who only need to discover what exists in Vault.

2. **Token Scoping**: Create dedicated Vault tokens for each agent with only the required permissions.

3. **Network Policies**: Consider implementing Kubernetes NetworkPolicies to restrict which pods can communicate with the MCP server.

4. **Audit Logging**: Enable Vault audit logging to track all operations performed through the agents.

5. **Secret Rotation**: Implement regular rotation of the Vault token stored in the Kubernetes secret.

---

## References

- [kagent Documentation](https://kagent.dev/docs/kagent)
- [kmcp Documentation](https://kagent.dev/docs/kmcp)
- [HashiCorp Vault MCP Server](https://developer.hashicorp.com/vault/docs/mcp-server)
- [A2A Protocol](https://a2a.guide)
- [Model Context Protocol](https://modelcontextprotocol.io)
