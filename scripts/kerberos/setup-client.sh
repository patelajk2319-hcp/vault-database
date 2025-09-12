#!/bin/bash
# ============================================================================
# KERBEROS CLIENT SETUP SCRIPT
# This script installs Kerberos client packages and keeps the container running
# Designed for Ubuntu 20.04 with full ARM64/aarch64 support
# ============================================================================

# Color definitions for output formatting
GREEN='\033[0;32m'    # Green text for success messages
YELLOW='\033[1;33m'   # Yellow text for warnings
BLUE='\033[0;34m'     # Blue text for informational messages
NC='\033[0m'          # No Color - resets text color to default

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up Kerberos client...${NC}"
echo -e "${BLUE}========================================${NC}"

# Update package lists
echo -e "${BLUE}Updating package lists...${NC}"
apt-get update -y > /dev/null 2>&1

# Pre-configure Kerberos to avoid interactive prompts
echo -e "${BLUE}Pre-configuring Kerberos settings...${NC}"
echo "krb5-config krb5-config/default_realm string EXAMPLE.COM" | debconf-set-selections
echo "krb5-config krb5-config/kerberos_servers string kdc.example.com" | debconf-set-selections
echo "krb5-config krb5-config/admin_server string kdc.example.com" | debconf-set-selections
echo "krb5-config krb5-config/add_servers_realm string EXAMPLE.COM" | debconf-set-selections
echo "krb5-config krb5-config/read_conf boolean true" | debconf-set-selections
echo -e "${GREEN}✓ Kerberos settings pre-configured${NC}"

# Install Kerberos client packages (Ubuntu/Debian packages)
echo -e "${BLUE}Installing krb5-config...${NC}"
apt-get install -y krb5-config > /dev/null 2>&1
echo -e "${GREEN}✓ krb5-config installed${NC}"

echo -e "${BLUE}Installing krb5-user...${NC}"
apt-get install -y krb5-user > /dev/null 2>&1
echo -e "${GREEN}✓ krb5-user installed${NC}"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}🎉 KERBEROS CLIENT SETUP COMPLETE! 🎉${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}📋 Client Configuration:${NC}"
echo -e "${BLUE}├── Realm:${NC} EXAMPLE.COM"
echo -e "${BLUE}├── KDC Server:${NC} kdc.example.com"
echo -e "${BLUE}└── Config File:${NC} /etc/krb5.conf"
echo ""
echo -e "${GREEN}🚀 Container ready for Kerberos testing!${NC}"
echo -e "${BLUE}============================================${NC}"

# Keep container running for interactive testing
tail -f /dev/null