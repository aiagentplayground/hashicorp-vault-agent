# Vault MCP Server Architecture

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (kagent)                              │
│                                                                              │
│  ┌────────────────┐                                                         │
│  │  AI Assistant  │                                                         │
│  │  (via kagent)  │                                                         │
│  └────────┬───────┘                                                         │
│           │                                                                  │
│           │ Discovers & Uses MCP Tools                                      │
│           ▼                                                                  │
│  ┌──────────────────────────────────────┐                                   │
│  │   RemoteMCPServer                    │                                   │
│  │   (vault-mcp-remote)                 │                                   │
│  │                                      │                                   │
│  │  Mount Management:                   │                                   │
│  │  - create_mount                      │                                   │
│  │  - list_mounts                       │                                   │
│  │  - delete_mount                      │                                   │
│  │                                      │                                   │
│  │  KV Operations:                      │                                   │
│  │  - read_secret                       │                                   │
│  │  - write_secret                      │                                   │
│  │  - list_secrets                      │                                   │
│  │  - delete_secret                     │                                   │
│  │                                      │                                   │
│  │  PKI Operations:                     │                                   │
│  │  - enable_pki                        │                                   │
│  │  - create_pki_issuer                 │                                   │
│  │  - issue_pki_certificate             │                                   │
│  │  - ... and more                      │                                   │
│  └───────────┬──────────────────────────┘                                   │
│              │                                                               │
│              │ HTTP POST to                                                 │
│              │ http://vault-mcp-server.kagent.svc:8084/mcp                 │
│              ▼                                                               │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │         Service: vault-mcp-server (ClusterIP)                  │        │
│  │                  Port: 8084                                     │        │
│  └────────────────────┬───────────────────────────────────────────┘        │
│                       │                                                     │
│                       ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐      │
│  │     Deployment: vault-mcp-server                                 │      │
│  │  ┌────────────────────────────────────────────────────────────┐  │      │
│  │  │  Pod: vault-mcp-server                                     │  │      │
│  │  │                                                              │  │      │
│  │  │  Container: vault-mcp                                       │  │      │
│  │  │  Image: sebbycorp/vault-mcp-server:latest                 │  │      │
│  │  │  (Built from HashiCorp Go source)                          │  │      │
│  │  │  Port: 8084                                                 │  │      │
│  │  │                                                              │  │      │
│  │  │  Environment:                                               │  │      │
│  │  │  - VAULT_ADDR=http://172.16.10.152:8200                    │  │      │
│  │  │  - VAULT_TOKEN=hvs.xVYhjPUczOmmRElkdZotFG11                │  │      │
│  │  │  - VAULT_SKIP_VERIFY=true                                  │  │      │
│  │  │                                                              │  │      │
│  │  │  vault-mcp-server binary                                    │  │      │
│  │  │  (HTTP mode on port 8084)                                   │  │      │
│  │  │                                                              │  │      │
│  │  │  HashiCorp Vault Client SDK                                 │  │      │
│  │  └────────────────┬─────────────────────────────────────────────┘  │      │
│  └───────────────────┼─────────────────────────────────────────────────┘      │
│                      │                                                        │
└──────────────────────┼────────────────────────────────────────────────────────┘
                       │
                       │ Vault HTTP API (port 8200)
                       │ /v1/sys/mounts/*
                       │ /v1/secret/*
                       │ /v1/pki/*
                       ▼
            ┌──────────────────────────┐
            │  HashiCorp Vault Server  │
            │  http://172.16.10.152    │
            │  :8200                   │
            │                          │
            │  - KV Secrets Engine     │
            │  - PKI Secrets Engine    │
            │  - Transit Engine        │
            │  - Auth Methods          │
            │  - Policies              │
            │  - Audit Logs            │
            └──────────────────────────┘
```

## How It Works

### 1. **AI Assistant Query**
   - User asks: "Store the database password in Vault"
   - kagent receives the request
   - Agent identifies the need to use secrets management tools

### 2. **kagent Discovers Tools**
   - kagent queries the RemoteMCPServer (`vault-mcp-remote`)
   - Discovers 14 available tools:
     - **Mount**: create_mount, list_mounts, delete_mount
     - **KV**: read_secret, write_secret, list_secrets, delete_secret
     - **PKI**: enable_pki, create_pki_issuer, list_pki_issuers, read_pki_issuer, create_pki_role, list_pki_roles, issue_pki_certificate

### 3. **kagent Calls MCP Server**
   - kagent sends HTTP POST to `http://vault-mcp-server.kagent.svc.cluster.local:8084/mcp`
   - JSON-RPC 2.0 payload with tool call:
     ```json
     {
       "jsonrpc": "2.0",
       "method": "tools/call",
       "params": {
         "name": "write_secret",
         "arguments": {
           "mount": "secret",
           "path": "myapp/database",
           "key": "password",
           "value": "super-secret-pass"
         }
       },
       "id": 1
     }
     ```

### 4. **Vault MCP Server Processing**
   - Receives the tool call request
   - Uses VAULT_ADDR and VAULT_TOKEN from environment
   - Creates Vault client connection to http://172.16.10.152:8200
   - Translates MCP call to Vault API call:
     ```
     PUT /v1/secret/data/myapp/database
     X-Vault-Token: hvs.xVYhjPUczOmmRElkdZotFG11

     {
       "data": {
         "password": "super-secret-pass"
       }
     }
     ```

### 5. **Vault Server Response**
   - Vault processes the request
   - Validates token permissions
   - Stores the secret in KV v2 engine
   - Returns success response with metadata:
     ```json
     {
       "data": {
         "created_time": "2024-01-21T10:00:00Z",
         "version": 1
       }
     }
     ```

### 6. **Response to AI Assistant**
   - MCP server formats Vault response
   - Returns to kagent via HTTP
   - kagent presents to AI assistant:
     ```
     Secret stored successfully at secret/myapp/database
     Version: 1
     You can retrieve it with: read_secret(mount="secret", path="myapp/database")
     ```

---

## Tool Categories and Workflows

### Mount Management Workflow

```
User: "Create a new KV mount for my application"
  │
  ▼
AI Assistant determines: Need to create mount
  │
  │ Calls: create_mount(type="kv-v2", path="myapp/")
  ▼
MCP Server
  │ POST /v1/sys/mounts/myapp
  │ {
  │   "type": "kv-v2",
  │   "description": "Application secrets"
  │ }
  ▼
Vault Server
  │ Creates mount at myapp/
  │ Returns success
  ▼
User sees: "Created KV v2 mount at myapp/. You can now store secrets there."
```

### Secret Storage Workflow

```
User: "Save the API key for our payment processor"
  │
  ▼
AI Assistant
  │ Asks: What's the API key value?
  │ User provides: "pk_live_abc123xyz"
  │
  │ Calls: write_secret(
  │   mount="secret",
  │   path="payment/api",
  │   key="api_key",
  │   value="pk_live_abc123xyz"
  │ )
  ▼
MCP Server
  │ PUT /v1/secret/data/payment/api
  │ {
  │   "data": {
  │     "api_key": "pk_live_abc123xyz"
  │   }
  │ }
  ▼
Vault Server
  │ Stores secret with versioning
  │ Creates version 1
  │ Returns metadata
  ▼
User sees:
  "Stored API key at secret/payment/api (version 1)
   Access it with: read_secret(mount='secret', path='payment/api')"
```

### Secret Retrieval Workflow

```
User: "Get the database password"
  │
  ▼
AI Assistant
  │ May ask: Which database? (if ambiguous)
  │ User clarifies: "Production MySQL"
  │
  │ Calls: read_secret(mount="secret", path="prod/mysql")
  ▼
MCP Server
  │ GET /v1/secret/data/prod/mysql
  │ Headers: X-Vault-Token: ...
  ▼
Vault Server
  │ Validates token permissions
  │ Retrieves latest version of secret
  │ Returns data and metadata
  ▼
User sees (if authorized):
  "Database credentials:
   - username: prod_user
   - password: [secret value]
   - host: mysql-prod.internal
   - port: 3306"
```

### PKI Certificate Workflow

```
User: "Issue a certificate for api.example.com"
  │
  ▼
AI Assistant
  │ 1. Check if PKI mount exists: list_mounts()
  │ 2. If no PKI, suggest: enable_pki(path="pki/")
  │ 3. Check for roles: list_pki_roles(mount="pki")
  │ 4. If no role, suggest creating one
  │
  │ Calls: issue_pki_certificate(
  │   mount="pki",
  │   role_name="web-server",
  │   common_name="api.example.com",
  │   ttl="8760h"
  │ )
  ▼
MCP Server
  │ POST /v1/pki/issue/web-server
  │ {
  │   "common_name": "api.example.com",
  │   "ttl": "8760h"
  │ }
  ▼
Vault Server (PKI)
  │ Validates role permissions
  │ Generates certificate using CA
  │ Returns certificate + private key + CA chain
  ▼
User receives:
  "Certificate issued successfully!

   Common Name: api.example.com
   Serial: 39:cd:2e:f7...
   Valid: 2024-01-21 to 2025-01-21

   Files:
   - certificate.pem
   - private_key.pem
   - ca_chain.pem

   Install instructions: [provides steps]"
```

---

## Vault API Translation

### MCP Tool → Vault API Mapping

| MCP Tool | Vault API Endpoint | HTTP Method |
|----------|-------------------|-------------|
| `create_mount` | `/v1/sys/mounts/{path}` | POST |
| `list_mounts` | `/v1/sys/mounts` | GET |
| `delete_mount` | `/v1/sys/mounts/{path}` | DELETE |
| `read_secret` | `/v1/{mount}/data/{path}` | GET |
| `write_secret` | `/v1/{mount}/data/{path}` | PUT/POST |
| `list_secrets` | `/v1/{mount}/metadata/{path}` | LIST |
| `delete_secret` | `/v1/{mount}/data/{path}` | DELETE |
| `enable_pki` | `/v1/sys/mounts/pki` | POST |
| `create_pki_issuer` | `/v1/{mount}/issuers/import/cert` | POST |
| `list_pki_issuers` | `/v1/{mount}/issuers` | LIST |
| `create_pki_role` | `/v1/{mount}/roles/{name}` | POST |
| `list_pki_roles` | `/v1/{mount}/roles` | LIST |
| `issue_pki_certificate` | `/v1/{mount}/issue/{role}` | POST |

### Authentication Flow

```
MCP Tool Call
     │
     ▼
Vault MCP Server
     │
     │ Gets VAULT_TOKEN from env
     │
     │ HTTP Request to Vault
     │ Header: X-Vault-Token: hvs.xVYhjPUczOmmRElkdZotFG11
     ▼
Vault Server
     │
     │ Validates token
     │ Checks token policies
     │ Verifies permissions for operation
     │
     ├─ Authorized → Execute operation
     │
     └─ Unauthorized → Return 403 Forbidden
```

---

## Security Architecture

### Token Permission Model

```
Root Token (DANGEROUS)
     │
     ├─ Full access to all paths
     ├─ Can create/delete mounts
     ├─ Can manage policies
     ├─ Can revoke any token
     └─ Should NEVER be used in production

Limited Token (RECOMMENDED)
     │
     ├─ Bound to specific policies
     │   ├─ mcp-server-policy
     │   │   ├─ sys/mounts/* (create, read, update, delete, list)
     │   │   ├─ secret/* (create, read, update, delete, list)
     │   │   └─ pki/* (create, read, update, delete, list)
     │   │
     │   └─ read-only-policy
     │       ├─ secret/* (read, list)
     │       └─ No write/delete permissions
     │
     ├─ Time-bound (TTL: 720h)
     ├─ Can be renewed
     └─ Can be revoked
```

### Secret Access Flow

```
1. AI Assistant Request
        ↓
2. kagent validates request
        ↓
3. MCP Server receives tool call
        ↓
4. MCP Server → Vault API
   (with token in header)
        ↓
5. Vault validates token
        ↓
6. Vault checks policy
   - Does token have permission for this path?
   - What capabilities? (read, write, delete, list)
        ↓
7. Vault executes operation
        ↓
8. Vault logs to audit log
   - Who accessed what
   - When
   - Result (success/failure)
        ↓
9. Response back through MCP Server
        ↓
10. AI Assistant presents result
```

### Network Security Layers

```
┌─────────────────────────────────────────┐
│  AI Assistant                            │
│  - No direct Vault access               │
│  - Goes through kagent                  │
└─────────┬───────────────────────────────┘
          │ HTTP (internal)
          ▼
┌─────────────────────────────────────────┐
│  kagent (Kubernetes)                     │
│  - Validates requests                   │
│  - Routes to MCP server                 │
└─────────┬───────────────────────────────┘
          │ HTTP (internal)
          ▼
┌─────────────────────────────────────────┐
│  Vault MCP Server Pod                    │
│  - Network Policy: Only egress to Vault │
│  - Secret mount: Read-only token        │
└─────────┬───────────────────────────────┘
          │ HTTP/HTTPS
          │ (could be restricted by firewall)
          ▼
┌─────────────────────────────────────────┐
│  Vault Server                            │
│  - TLS encryption                       │
│  - Token-based auth                     │
│  - Policy enforcement                   │
│  - Audit logging                        │
└─────────────────────────────────────────┘
```

---

## Performance Characteristics

### Connection Management
- **HTTP Keep-Alive**: Vault client maintains persistent connections
- **First request**: ~100-200ms (connection + auth)
- **Subsequent requests**: ~20-50ms (reuse connection)

### Operation Latencies
| Operation | Typical Latency |
|-----------|----------------|
| list_mounts | 20-50ms |
| read_secret | 30-80ms |
| write_secret | 40-100ms |
| list_secrets | 30-100ms |
| issue_certificate | 100-300ms |

### Caching Considerations
- **No caching**: All operations go directly to Vault
- **Vault handles caching**: Internal caching for improved performance
- **Versioning**: KV v2 stores all versions (no overwrites)

### Scaling Patterns
```
Single Replica (Low Load)
┌────────────────┐
│ MCP Server Pod │ → Vault
└────────────────┘

Multiple Replicas (High Availability)
┌────────────────┐
│ MCP Server (1) │ ↘
└────────────────┘   ↘
┌────────────────┐     → Vault (handles concurrent connections)
│ MCP Server (2) │   ↗
└────────────────┘ ↗
┌────────────────┐
│ MCP Server (3) │
└────────────────┘
```

---

## Deployment Patterns

### Development Setup
```
Kubernetes Cluster
├── vault-mcp-server (1 replica)
│   └── Connects to dev Vault
│       - Root token (acceptable for dev)
│       - No TLS (acceptable for dev)
│       - VAULT_SKIP_VERIFY=true
│
└── Vault Dev Server
    - docker run vault:latest
    - In-memory storage
    - Root token only
```

### Production Setup
```
Kubernetes Cluster
├── vault-mcp-server (3 replicas)
│   ├── Limited token (policy-based)
│   ├── TLS verification enabled
│   ├── Token auto-renewal
│   └── Audit logging enabled
│
└── External Vault Cluster (HA)
    ├── Vault Server 1 (Leader)
    ├── Vault Server 2 (Standby)
    ├── Vault Server 3 (Standby)
    ├── Raft storage backend
    ├── TLS certificates
    └── Multiple auth methods
```

---

## Comparison with Other MCP Servers

| Feature | Vault MCP | F5 MCP | PyATS MCP |
|---------|-----------|---------|-----------|
| **Language** | Go | Python | Python |
| **Source** | HashiCorp official | Custom wrapper | Custom wrapper |
| **Transport** | HTTP | HTTP | HTTP |
| **Auth Method** | Token | Basic auth | SSH keys |
| **External Service** | Vault server | F5 BIG-IP | Cisco devices |
| **Port** | 8084 | 8081 | 8083 |
| **Tool Count** | 14 | 3 | 5 |
| **Use Case** | Secrets mgmt | Load balancing | Network automation |

---

## Troubleshooting Architecture

### Debug Flow

1. **Check Pod Status**
   ```bash
   kubectl get pods -n kagent -l app=vault-mcp-server
   ```

2. **Verify Service Registration**
   ```bash
   kubectl get remotemcpserver vault-mcp-remote -n kagent
   ```

3. **Test MCP Endpoint**
   ```bash
   curl -X POST http://vault-mcp-server.kagent.svc:8084/mcp \
     -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
   ```

4. **Test Vault Connectivity**
   ```bash
   kubectl exec deployment/vault-mcp-server -n kagent -- \
     wget -O- http://172.16.10.152:8200/v1/sys/health
   ```

5. **Verify Token**
   ```bash
   kubectl exec deployment/vault-mcp-server -n kagent -- sh -c \
     'wget --header="X-Vault-Token: $VAULT_TOKEN" -O- $VAULT_ADDR/v1/sys/auth'
   ```

6. **Check Vault Audit Logs**
   - Review Vault server audit logs for permission denials
   - Check token capabilities

This architecture provides a secure, scalable foundation for AI-powered secrets management with HashiCorp Vault!
