#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}===================================${NC}"
echo -e "${YELLOW}Vault MCP Server Cleanup${NC}"
echo -e "${YELLOW}===================================${NC}"
echo ""

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}This will remove all Vault MCP Server resources from the kagent namespace:${NC}"
echo "  - Agent (vault-secrets-agent)"
echo "  - RemoteMCPServer (vault-mcp-remote)"
echo "  - Service (vault-mcp-server)"
echo "  - Deployment (vault-mcp-server)"
echo "  - Secret (vault-credentials)"
echo ""

read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}Removing Agent...${NC}"
kubectl delete -f "$SCRIPT_DIR/vault-secrets-agent.yaml" --ignore-not-found=true

echo -e "${GREEN}Removing RemoteMCPServer...${NC}"
kubectl delete -f "$SCRIPT_DIR/remotemcpserver.yaml" --ignore-not-found=true

echo -e "${GREEN}Removing Service...${NC}"
kubectl delete -f "$SCRIPT_DIR/service.yaml" --ignore-not-found=true

echo -e "${GREEN}Removing Deployment...${NC}"
kubectl delete -f "$SCRIPT_DIR/deployment.yaml" --ignore-not-found=true

echo -e "${GREEN}Removing Secret...${NC}"
kubectl delete -f "$SCRIPT_DIR/secret.yaml" --ignore-not-found=true

echo ""
echo -e "${GREEN}===================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}===================================${NC}"
echo ""

echo "Verifying removal:"
kubectl get deployment,service,secret,remotemcpserver,agent -n kagent -l app=vault-mcp-server 2>&1 | grep -q "No resources found" && echo "All resources removed successfully" || echo "Some resources may still exist"
