#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===================================${NC}"
echo -e "${GREEN}Vault MCP Server Deployment for kagent${NC}"
echo -e "${GREEN}===================================${NC}"
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check if kagent namespace exists
if ! kubectl get namespace kagent &> /dev/null; then
    echo -e "${RED}Error: kagent namespace does not exist${NC}"
    echo -e "${YELLOW}Please install kagent first${NC}"
    exit 1
fi

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to check if secret needs to be configured
check_secret() {
    if grep -q "aHZzLnhWWWhqUFVjek9tbVJFbGtkWm90RkcxMQ==" "$SCRIPT_DIR/secret.yaml"; then
        echo -e "${YELLOW}Warning: You are using the default Vault token and address${NC}"
        echo -e "${YELLOW}Please update secret.yaml with your Vault credentials${NC}"
        echo ""
        echo "To encode your credentials:"
        echo "  echo -n 'http://your-vault-addr:8200' | base64"
        echo "  echo -n 'your-vault-token' | base64"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check secret configuration
check_secret

echo -e "${GREEN}Step 1: Deploying Vault credentials secret...${NC}"
kubectl apply -f "$SCRIPT_DIR/secret.yaml"
echo ""

echo -e "${GREEN}Step 2: Deploying Vault MCP Server...${NC}"
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"
echo ""

echo -e "${GREEN}Step 3: Creating service...${NC}"
kubectl apply -f "$SCRIPT_DIR/service.yaml"
echo ""

echo -e "${GREEN}Step 4: Registering with kagent...${NC}"
kubectl apply -f "$SCRIPT_DIR/remotemcpserver.yaml"
echo ""

echo -e "${GREEN}Step 5: Deploying Vault secrets agent...${NC}"
kubectl apply -f "$SCRIPT_DIR/vault-secrets-agent.yaml"
echo ""

echo -e "${GREEN}Step 6: Waiting for deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=120s deployment/vault-mcp-server -n kagent
echo ""

echo -e "${GREEN}===================================${NC}"
echo -e "${GREEN}Deployment Status${NC}"
echo -e "${GREEN}===================================${NC}"
echo ""

echo "Deployment:"
kubectl get deployment vault-mcp-server -n kagent
echo ""

echo "Pods:"
kubectl get pods -n kagent -l app=vault-mcp-server
echo ""

echo "Service:"
kubectl get service vault-mcp-server -n kagent
echo ""

echo "RemoteMCPServer:"
kubectl get remotemcpserver vault-mcp-remote -n kagent
echo ""

echo "Agent:"
kubectl get agent vault-secrets-agent -n kagent
echo ""

echo -e "${GREEN}===================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}===================================${NC}"
echo ""

echo "To view logs:"
echo "  kubectl logs -n kagent -l app=vault-mcp-server --tail=50"
echo ""

echo "To test with kagent:"
echo "  Ask your agent: 'List all mounts in Vault'"
echo "  Or: 'Store a secret for myapp database password'"
echo "  Or: 'Issue a certificate for example.com'"
echo ""

echo "For troubleshooting, see: $SCRIPT_DIR/README.md"
