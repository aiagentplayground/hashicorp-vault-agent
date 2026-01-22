# Vault MCP Server Kubernetes Deployment

Deploy the HashiCorp Vault MCP Server to your Kubernetes cluster with kagent integration for secrets management and PKI operations.

## Architecture

The architecture consists of:

- **AI Assistant**: kagent-powered assistant that discovers and orchestrates Vault tools
- **RemoteMCPServer**: Kubernetes CRD that registers the Vault MCP server with kagent
- **Service**: ClusterIP service exposing the MCP server on port 8084
- **Deployment**: Container running the Vault MCP server (built from HashiCorp's Go codebase)
- **Secret**: Stores Vault address and authentication token
- **Vault Server**: External HashiCorp Vault server for secrets management

## Components

| Component | Type | Description |
|-----------|------|-------------|
| `vault-mcp-server` | Deployment | Main MCP server container (Go binary) |
| `vault-mcp-server` | Service | ClusterIP service exposing port 8084 |
| `vault-credentials` | Secret | Vault address and token |
| `vault-mcp-remote` | RemoteMCPServer | kagent CRD for MCP server registration |
| `vault-secrets-agent` | Agent | Declarative secrets management agent |

## Prerequisites

1. **Kubernetes cluster** with `kubectl` access
2. **kagent** installed in the `kagent` namespace
   ```bash
   kubectl get namespace kagent
   ```
3. **HashiCorp Vault** server accessible from the cluster
4. **Vault token** with appropriate permissions (root token for full functionality)
5. **Network connectivity** from cluster to Vault server

## Quick Start

### Step 1: Configure Vault Credentials

Edit `secret.yaml` and update the base64-encoded values:

```bash
# Encode your Vault address (include protocol and port)
echo -n "http://172.16.10.152:8200" | base64

# Encode your Vault token
echo -n "hvs.xVYhjPUczOmmRElkdZotFG11" | base64
```

Update `secret.yaml` with your encoded values:
```yaml
data:
  VAULT_ADDR: <base64-encoded-address>
  VAULT_TOKEN: <base64-encoded-token>
```

**Security Note**: For production, use a token with limited permissions, not the root token. Consider using Kubernetes auth method or external secret management.

### Step 2: Deploy Using Script

Use the provided deployment script:

```bash
chmod +x deploy.sh
./deploy.sh
```

Or deploy manually:

```bash
# Create the secret
kubectl apply -f secret.yaml

# Deploy the MCP server
kubectl apply -f deployment.yaml

# Create the service
kubectl apply -f service.yaml

# Register with kagent
kubectl apply -f remotemcpserver.yaml

# Deploy the secrets agent
kubectl apply -f vault-secrets-agent.yaml
```

### Step 3: Verify Deployment

Check that all resources are running:

```bash
# Check deployment status
kubectl get deployment vault-mcp-server -n kagent

# Check pod status
kubectl get pods -n kagent -l app=vault-mcp-server

# Check service
kubectl get service vault-mcp-server -n kagent

# Check RemoteMCPServer registration
kubectl get remotemcpserver vault-mcp-remote -n kagent

# Check Agent
kubectl get agent vault-secrets-agent -n kagent

# View pod logs
kubectl logs -n kagent -l app=vault-mcp-server --tail=50
```

Expected output:
```
NAME                 READY   STATUS    RESTARTS   AGE
vault-mcp-server     1/1     Running   0          30s
```

### Step 4: Test with kagent

Ask your kagent agent to interact with Vault:

**Secrets Management:**
```
"List all mounts in Vault"
"Store a secret for database password"
"Read the secret at secret/myapp/db"
"Create a new KV v2 mount at myapp/"
```

**Mount Operations:**
```
"What secret engines are enabled?"
"Create a KV mount at secret/prod/"
"Delete the mount at secret/test/"
```

**PKI Operations:**
```
"Enable PKI at pki/"
"Create a PKI role for example.com"
"Issue a certificate for api.example.com"
"List all PKI roles"
```

## Configuration Details

### Environment Variables

The deployment uses these environment variables from the secret:

| Variable | Description | Example |
|----------|-------------|---------|
| `VAULT_ADDR` | Vault server address (with protocol and port) | `http://172.16.10.152:8200` |
| `VAULT_TOKEN` | Vault authentication token | `hvs.xVYhjPUczOmmRElkdZotFG11` |
| `VAULT_SKIP_VERIFY` | Skip TLS verification (for self-signed certs) | `true` |

### Resource Limits

Default resource configuration:

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

Adjust these in `deployment.yaml` based on your needs.

### Network Requirements

The Vault MCP Server requires:
- Outbound HTTP/HTTPS access to Vault server (port 8200 typically)
- Inbound HTTP (8084) access from kagent
- DNS resolution within the cluster

## Available MCP Tools

Once deployed, the following tools are available to kagent:

### Mount Management
| Tool | Description | Parameters |
|------|-------------|------------|
| `create_mount` | Create new secrets engine mount | `type`, `path`, `description` |
| `list_mounts` | List all configured mounts | None |
| `delete_mount` | Remove a mount (destructive) | `path` |

### Key-Value Operations
| Tool | Description | Parameters |
|------|-------------|------------|
| `read_secret` | Retrieve secret data | `mount`, `path` |
| `write_secret` | Store or update secret | `mount`, `path`, `key`, `value` |
| `list_secrets` | List secrets in mount | `mount`, `path` |
| `delete_secret` | Delete secret or key | `mount`, `path`, `key` |

### PKI Certificate Management
| Tool | Description | Parameters |
|------|-------------|------------|
| `enable_pki` | Enable PKI engine | `path`, `description` |
| `create_pki_issuer` | Create/import CA issuer | `mount`, `issuer_name`, `certificate`, `private_key` |
| `list_pki_issuers` | List all issuers | `mount` |
| `read_pki_issuer` | Get issuer details | `mount`, `issuer_name` |
| `create_pki_role` | Create certificate role | `mount`, `role_name`, `allowed_domains`, `ttl` |
| `list_pki_roles` | List all roles | `mount` |
| `issue_pki_certificate` | Issue certificate | `mount`, `role_name`, `common_name`, `alt_names`, `ttl` |

## Troubleshooting

### Pod not starting

```bash
# Check pod events
kubectl describe pod -n kagent -l app=vault-mcp-server

# Check logs
kubectl logs -n kagent -l app=vault-mcp-server
```

Common issues:
- Vault server not reachable from cluster
- Invalid Vault token
- Network policies blocking egress

### Connection errors to Vault

```bash
# Test Vault connectivity from pod
kubectl exec -n kagent deployment/vault-mcp-server -- \
  wget -O- http://172.16.10.152:8200/v1/sys/health
```

Common issues:

1. **Connection timeout** - Vault not reachable
   ```bash
   # Check network policies
   kubectl get networkpolicies -n kagent
   ```

2. **Authentication failed** - Wrong token
   ```bash
   # Verify token works from pod
   kubectl exec -n kagent deployment/vault-mcp-server -- \
     sh -c 'wget --header="X-Vault-Token: $VAULT_TOKEN" -O- $VAULT_ADDR/v1/sys/auth'
   ```

3. **SSL verification issues** - Self-signed certificate
   - Verify `VAULT_SKIP_VERIFY=true` is set in deployment

### kagent not seeing MCP server

```bash
# Check RemoteMCPServer status
kubectl describe remotemcpserver vault-mcp-remote -n kagent

# Check service endpoints
kubectl get endpoints vault-mcp-server -n kagent

# Test service connectivity
kubectl run -n kagent test-pod --rm -it --image=curlimages/curl -- \
  curl http://vault-mcp-server:8084/health
```

### Tool execution errors

Check Vault audit logs for permission issues:
```bash
# From Vault server
vault audit list
vault read sys/audit/file/log
```

Verify token has required permissions:
```bash
# Check token capabilities
vault token capabilities <token> sys/mounts
vault token capabilities <token> secret/data/myapp
```

## Updating the Deployment

### Update Vault Credentials

```bash
# Update secret
kubectl apply -f secret.yaml

# Restart deployment to pick up new secret
kubectl rollout restart deployment/vault-mcp-server -n kagent
```

### Update Docker Image

```bash
# Update image in deployment.yaml, then
kubectl apply -f deployment.yaml

# Or force pull latest
kubectl rollout restart deployment/vault-mcp-server -n kagent
```

### Update Agent Configuration

```bash
# Modify vault-secrets-agent.yaml, then
kubectl apply -f vault-secrets-agent.yaml
```

## Uninstalling

Remove all resources using cleanup script:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

Or manually:

```bash
kubectl delete -f vault-secrets-agent.yaml
kubectl delete -f remotemcpserver.yaml
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml
kubectl delete -f secret.yaml
```

## Security Considerations

1. **Token Permissions**:
   - **CRITICAL**: The provided setup uses root token - extremely privileged
   - Create limited tokens with specific policies for production
   - Use Kubernetes auth method for dynamic token generation
   - Rotate tokens regularly

2. **Secrets Management**:
   - Store credentials in external secret managers (Vault, AWS Secrets Manager)
   - Use Kubernetes service accounts with Vault auth
   - Enable audit logging in Vault

3. **Network Policies**:
   - Restrict pod egress to Vault IP only
   - Limit ingress to kagent namespace

4. **TLS/SSL**:
   - Use proper TLS certificates in production
   - Set `VAULT_SKIP_VERIFY=false` when using valid certs
   - Consider mutual TLS

5. **RBAC**:
   - Pod service account needs minimal permissions
   - Use Vault policies for fine-grained access control

## Vault Token Best Practices

### Creating a Limited Token

Instead of root token, create a token with specific policies:

```bash
# Create policy file
cat > mcp-policy.hcl <<EOF
# Allow mount management
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow KV operations
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow PKI operations
path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# Write policy to Vault
vault policy write mcp-server mcp-policy.hcl

# Create token with policy
vault token create -policy=mcp-server -ttl=720h
```

Use the generated token in `secret.yaml`.

### Using Kubernetes Auth

Enable Kubernetes auth in Vault:

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

# Create role
vault write auth/kubernetes/role/mcp-server \
    bound_service_account_names=vault-mcp-server \
    bound_service_account_namespaces=kagent \
    policies=mcp-server \
    ttl=1h
```

Modify deployment to use Kubernetes service account authentication.

## Performance Tuning

For high-volume operations:

1. **Increase Resources**:
   ```yaml
   resources:
     limits:
       memory: "1Gi"
       cpu: "1000m"
   ```

2. **Connection Pooling**: Vault client maintains persistent connections

3. **Caching**: Consider caching frequently accessed secrets

4. **Rate Limiting**: Implement rate limiting for secret operations

## Additional Resources

- [kagent Documentation](https://kagent.dev)
- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault MCP Server GitHub](https://github.com/hashicorp/vault-mcp-server)
- [Vault API Reference](https://developer.hashicorp.com/vault/api-docs)
- [Vault Policies Guide](https://developer.hashicorp.com/vault/docs/concepts/policies)

## Support

For issues or questions:
- Check logs: `kubectl logs -l app=vault-mcp-server -n kagent`
- Verify Vault connectivity: Test from pod
- Check Vault audit logs: For permission issues
- Review token capabilities: Ensure sufficient permissions
- Test MCP endpoints: Use curl from debug pod
