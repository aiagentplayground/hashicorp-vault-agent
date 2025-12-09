# HashiCorp Vault MCP Server and Agents with kagent

This guide explains how to deploy the HashiCorp Vault MCP Server on Kubernetes using kmcp, create AI agents that interact with Vault, and extend them with container-based skills.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Part 1: Deploy the Vault MCP Server](#part-1-deploy-the-vault-mcp-server)
- [Part 2: Deploy Vault Agents](#part-2-deploy-vault-agents)
- [Part 3: Add Container-Based Skills](#part-3-add-container-based-skills)
- [Part 4: Testing the Agents](#part-4-testing-the-agents)
- [Troubleshooting](#troubleshooting)

---

## Overview

This setup consists of the following components:

1. **Vault MCP Server** - A Model Context Protocol server that provides AI models with access to HashiCorp Vault APIs for managing secrets, mounts, and PKI certificates.

2. **Vault Expert Agent** - A full-featured agent that can create, read, update, and delete secrets, manage mounts, and handle PKI operations.

3. **Vault List Agent** - A read-only agent that can only list mounts and secrets (no write or delete operations).

4. **Container-Based Skills** - Reusable skill containers that extend agent capabilities with specialized workflows.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        kagent Agent                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Skills    │  │    Tools    │  │     System Message      │  │
│  │ (Container) │  │ (MCP Server)│  │    (Instructions)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │                  │
         ▼                  ▼
┌─────────────────┐  ┌──────────────────┐     ┌─────────────────┐
│  Skill Scripts  │  │  Vault MCP       │────▶│  HashiCorp      │
│  & Resources    │  │  Server          │     │  Vault          │
└─────────────────┘  └──────────────────┘     └─────────────────┘
```

---

## Prerequisites

Before you begin, ensure you have:

- A Kubernetes cluster (kind, minikube, EKS, GKE, etc.)
- `kubectl` configured to access your cluster
- Docker installed (for building skill containers)
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

## Part 3: Add Container-Based Skills

Skills are descriptions of capabilities that help agents act more autonomously. They guide the agent's tool usage and planning by orienting responses toward goals rather than just reacting to prompts.

### Step 1: Create a Vault Secret Rotation Skill

This skill helps automate secret rotation workflows.

1. Create the skill directory:

```bash
mkdir vault-rotation-skill
cd vault-rotation-skill
```

2. Create the `SKILL.md` file:

```bash
cat > SKILL.md <<'EOF'
---
name: vault-secret-rotation
description: Automate secret rotation workflows in HashiCorp Vault
---

# Vault Secret Rotation Skill

Use this skill when users want to rotate secrets in HashiCorp Vault following best practices.

## Instructions

- Expect the user to provide the secret path they wish to rotate
- Optionally they may supply a new value, but if not provided, generate a secure random value
- The script `scripts/rotate-secret.py` handles the rotation workflow

## Workflow

1. Read the current secret (for backup/audit purposes)
2. Generate or use provided new secret value
3. Write the new secret to Vault
4. Verify the rotation was successful
5. Output a summary (without exposing the actual secret values)

## Example

User: Rotate the database password at secret/myapp/database

Agent: 
1. Reads current secret metadata
2. Invokes `scripts/rotate-secret.py secret/myapp/database password`
3. Applies the rotation
4. Confirms success to user

## Security Notes

- Never output actual secret values to the user
- Always confirm before performing rotation
- Suggest updating dependent applications after rotation
EOF
```

3. Create the rotation script:

```bash
mkdir scripts
cat > scripts/rotate-secret.py <<'EOF'
#!/usr/bin/env python3
"""
Vault Secret Rotation Helper Script
Generates rotation commands and validates inputs
"""

import sys
import secrets
import string
import json
from datetime import datetime

def generate_secure_password(length=32):
    """Generate a cryptographically secure password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def generate_rotation_plan(secret_path, key_name, new_value=None):
    """Generate a rotation plan for the agent to execute"""
    
    if new_value is None:
        new_value = generate_secure_password()
    
    plan = {
        "timestamp": datetime.utcnow().isoformat(),
        "secret_path": secret_path,
        "key_to_rotate": key_name,
        "steps": [
            f"1. Read current secret at {secret_path} for audit log",
            f"2. Update key '{key_name}' with new value",
            f"3. Verify secret was updated successfully",
            f"4. Recommend updating dependent applications"
        ],
        "vault_write_command": f"vault kv put {secret_path} {key_name}=<new_value>",
        "new_value_generated": new_value is not None
    }
    
    # Write plan to file for agent to read
    with open("rotation-plan.json", "w") as f:
        json.dump(plan, f, indent=2)
    
    print(f"Rotation plan generated for: {secret_path}")
    print(f"Key to rotate: {key_name}")
    print(f"Plan saved to: rotation-plan.json")
    print("\nThe agent should now execute the rotation using Vault tools.")
    
    return plan

def print_usage():
    print("""Vault Secret Rotation Helper

Usage:
    python rotate-secret.py <secret_path> <key_name> [new_value]

Examples:
    python rotate-secret.py secret/myapp/db password
    python rotate-secret.py secret/api/keys api_key "custom-value-123"

This script generates a rotation plan that the agent will execute.
""")

if __name__ == "__main__":
    args = sys.argv[1:]
    
    if not args or "-h" in args or "--help" in args:
        print_usage()
        sys.exit(0)
    
    if len(args) < 2:
        print("Error: Need <secret_path> <key_name>")
        print_usage()
        sys.exit(1)
    
    secret_path = args[0]
    key_name = args[1]
    new_value = args[2] if len(args) > 2 else None
    
    generate_rotation_plan(secret_path, key_name, new_value)
EOF

chmod +x scripts/rotate-secret.py
```

4. Create the Dockerfile:

```bash
cat > Dockerfile <<'EOF'
FROM scratch
COPY . /
EOF
```

5. Build and push the skill container:

```bash
# Start local registry if not running
docker ps | grep registry || docker run -d -p 5000:5000 --restart=always --name local-registry registry:2

# Build and push
docker build -t localhost:5000/vault-rotation-skill:latest .
docker push localhost:5000/vault-rotation-skill:latest

# Go back to parent directory
cd ..
```

### Step 2: Create a Vault Policy Generator Skill

This skill helps generate Vault ACL policies.

1. Create the skill directory:

```bash
mkdir -p vault-policy-skill/scripts
cd vault-policy-skill
```

2. Create the `SKILL.md` file:

```bash
cat > SKILL.md <<'EOF'
---
name: vault-policy-generator
description: Generate HashiCorp Vault ACL policies based on requirements
---

# Vault Policy Generator Skill

Use this skill when users want to create Vault ACL policies.

## Instructions

- Expect the user to describe what access they need
- Use the script `scripts/generate-policy.py` to create policy HCL
- The script outputs a valid Vault policy file

## Parameters

- `policy_name`: Name for the policy
- `paths`: Comma-separated list of paths to grant access to
- `capabilities`: Comma-separated capabilities (read, write, list, delete, sudo)

## Example

User: Create a read-only policy for the apps/ secrets path

Agent: Invokes `scripts/generate-policy.py apps-readonly secret/data/apps/* read,list`

The skill generates a `policy.hcl` file that can be applied to Vault.

## Output

Apply the generated policy with:

\`\`\`bash
vault policy write <policy_name> policy.hcl
\`\`\`
EOF
```

3. Create the policy generator script:

```bash
cat > scripts/generate-policy.py <<'EOF'
#!/usr/bin/env python3
"""
Vault Policy Generator
Creates HCL policy files based on requirements
"""

import sys
from pathlib import Path

def generate_policy(policy_name, paths, capabilities):
    """Generate a Vault ACL policy in HCL format"""
    
    policy_blocks = []
    
    for path in paths:
        caps = ', '.join(f'"{c.strip()}"' for c in capabilities)
        block = f'''path "{path}" {{
  capabilities = [{caps}]
}}'''
        policy_blocks.append(block)
    
    policy_content = f'''# Vault ACL Policy: {policy_name}
# Generated by vault-policy-skill
# 
# Apply with: vault policy write {policy_name} policy.hcl

{chr(10).join(policy_blocks)}
'''
    
    # Write policy to file
    policy_file = Path("policy.hcl")
    policy_file.write_text(policy_content)
    
    print(f"Policy '{policy_name}' generated successfully!")
    print(f"Output file: policy.hcl")
    print(f"\nPolicy content:")
    print("-" * 40)
    print(policy_content)
    print("-" * 40)
    print(f"\nTo apply: vault policy write {policy_name} policy.hcl")
    
    return policy_content

def print_usage():
    print("""Vault Policy Generator

Usage:
    python generate-policy.py <policy_name> <paths> <capabilities>

Arguments:
    policy_name  - Name for the policy
    paths        - Comma-separated secret paths (supports wildcards)
    capabilities - Comma-separated capabilities

Capabilities:
    read, write, list, delete, sudo, create, update, patch

Examples:
    python generate-policy.py app-readonly "secret/data/apps/*" "read,list"
    python generate-policy.py admin "secret/*,auth/*" "read,write,list,delete"
""")

if __name__ == "__main__":
    args = sys.argv[1:]
    
    if not args or "-h" in args or "--help" in args:
        print_usage()
        sys.exit(0)
    
    if len(args) < 3:
        print("Error: Need <policy_name> <paths> <capabilities>")
        print_usage()
        sys.exit(1)
    
    policy_name = args[0]
    paths = [p.strip() for p in args[1].split(",")]
    capabilities = [c.strip() for c in args[2].split(",")]
    
    generate_policy(policy_name, paths, capabilities)
EOF

chmod +x scripts/generate-policy.py
```

4. Create the Dockerfile and build:

```bash
cat > Dockerfile <<'EOF'
FROM scratch
COPY . /
EOF

# Build and push
docker build -t localhost:5000/vault-policy-skill:latest .
docker push localhost:5000/vault-policy-skill:latest

# Go back to parent directory
cd ..
```

### Step 3: Deploy Agent with Skills

Update the Vault Expert Agent to include the container-based skills:

```bash
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: vault-expert-agent-with-skills
  namespace: kagent
spec:
  description: A HashiCorp Vault expert agent with advanced skills for secret rotation and policy management.
  type: Declarative
  skills:
    insecureSkipVerify: true
    refs:
      - kind-registry:5000/vault-rotation-skill:latest
      - kind-registry:5000/vault-policy-skill:latest
  declarative:
    modelConfig: default-model-config
    systemMessage: |-
      You are an expert HashiCorp Vault agent with advanced skills for managing secrets, policies, and automation workflows.
      
      # Capabilities
      You can help users with:
      - Creating, listing, and deleting secret mounts (KV v1, KV v2)
      - Reading, writing, listing, and deleting secrets in KV mounts
      - Managing PKI secrets engine
      - **Rotating secrets** using the vault-secret-rotation skill
      - **Generating ACL policies** using the vault-policy-generator skill
      
      # Skills Available
      You have access to container-based skills that provide specialized workflows:
      1. **vault-secret-rotation**: Automate secret rotation with best practices
      2. **vault-policy-generator**: Generate Vault ACL policies from requirements
      
      # Instructions
      - Check your skills using the SkillsTool when asked about capabilities
      - Use skills for complex workflows (rotation, policy generation)
      - Use MCP tools for direct Vault operations
      - Always explain what you're doing before executing
      - Confirm destructive operations with the user
      
      # Security Best Practices
      - Never expose secret values in outputs
      - Recommend least-privilege access patterns
      - Suggest secret rotation schedules
      
      # Response format
      - ALWAYS format your response as Markdown
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
    a2aConfig:
      skills:
        - id: secrets-management
          name: Secrets Management
          description: Full lifecycle management of secrets in Vault
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - secrets
          examples:
            - "Store a new database credential"
            - "Rotate the API key for my application"
            - "List all secrets in the production path"
        - id: policy-management
          name: Policy Management
          description: Create and manage Vault ACL policies
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - policies
            - acl
          examples:
            - "Create a read-only policy for the dev team"
            - "Generate an admin policy for the platform team"
        - id: secret-rotation
          name: Secret Rotation
          description: Automated secret rotation workflows
          inputModes:
            - text
          outputModes:
            - text
          tags:
            - vault
            - rotation
            - automation
          examples:
            - "Rotate the database password"
            - "Set up rotation for API keys"
EOF
```

> **Note**: For Kind clusters, use `kind-registry:5000` instead of `localhost:5000`. For other registries (Docker Hub, GHCR, ECR), update the image references accordingly.

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

# Test skills
kagent invoke --agent vault-expert-agent-with-skills --task "What skills do you have?"
kagent invoke --agent vault-expert-agent-with-skills --task "Generate a read-only policy for secret/apps/*"
kagent invoke --agent vault-expert-agent-with-skills --task "Rotate the password at secret/myapp/database"
```

### Option 3: Using the A2A Protocol

```bash
# Port-forward the kagent controller
kubectl port-forward svc/kagent-controller 8083:8083 -n kagent

# Get the agent card
curl localhost:8083/api/a2a/kagent/vault-expert-agent/.well-known/agent.json | jq

# Get the skilled agent card
curl localhost:8083/api/a2a/kagent/vault-expert-agent-with-skills/.well-known/agent.json | jq
```

### Option 4: Using the A2A Host CLI

```bash
# Clone the A2A samples repository
git clone https://github.com/a2aproject/a2a-samples.git
cd a2a-samples/samples/python/hosts/cli

# Connect to the vault expert agent with skills
uv run . --agent http://127.0.0.1:8083/api/a2a/kagent/vault-expert-agent-with-skills
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

### Skills Not Loading

```bash
# Check if skill images are accessible
docker pull localhost:5000/vault-rotation-skill:latest

# For Kind clusters, ensure registry is accessible
kubectl get pods -n kagent -l app.kubernetes.io/name=vault-expert-agent-with-skills -o yaml | grep -A 10 initContainers

# Check agent logs for skill loading errors
kubectl logs -n kagent -l app.kubernetes.io/name=vault-expert-agent-with-skills
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

| Feature | Vault List Agent | Vault Expert Agent | Expert + Skills |
|---------|------------------|-------------------|-----------------|
| List mounts | ✅ | ✅ | ✅ |
| List secrets | ✅ | ✅ | ✅ |
| Read secrets | ❌ | ✅ | ✅ |
| Write secrets | ❌ | ✅ | ✅ |
| Delete secrets | ❌ | ✅ | ✅ |
| Create mounts | ❌ | ✅ | ✅ |
| PKI management | ❌ | ✅ | ✅ |
| Secret rotation | ❌ | ❌ | ✅ |
| Policy generation | ❌ | ❌ | ✅ |
| Use case | Audit/Discovery | Administration | Full Automation |

---

## Security Considerations

1. **Least Privilege**: Use the List Agent for users who only need to discover what exists in Vault.

2. **Token Scoping**: Create dedicated Vault tokens for each agent with only the required permissions.

3. **Network Policies**: Consider implementing Kubernetes NetworkPolicies to restrict which pods can communicate with the MCP server.

4. **Audit Logging**: Enable Vault audit logging to track all operations performed through the agents.

5. **Secret Rotation**: Implement regular rotation of the Vault token stored in the Kubernetes secret.

6. **Skill Security**: Review all skill scripts before deploying to ensure they don't expose sensitive data.

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

# Remove skill images
docker rmi localhost:5000/vault-rotation-skill:latest
docker rmi localhost:5000/vault-policy-skill:latest

# Remove skill directories
rm -rf vault-rotation-skill vault-policy-skill
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
