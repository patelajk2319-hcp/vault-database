#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Extracting Kerberos files for Vault...${NC}"

# Wait for KDC files with more comprehensive checking
max_attempts=60  # Increased timeout
attempt=0

echo -e "${BLUE}Waiting for KDC to create keytab and config files...${NC}"

while [ $attempt -lt $max_attempts ]; do
    # Check if files exist and are not empty
    if [ -f /kdc-data/vault.keytab ] && [ -s /kdc-data/vault.keytab ] && [ -f /kdc-data/krb5.conf ] && [ -s /kdc-data/krb5.conf ]; then
        echo -e "${GREEN}✅ KDC files found and non-empty${NC}"
        
        # Additional check - verify keytab has reasonable size (> 100 bytes)
        keytab_size=$(stat -c%s /kdc-data/vault.keytab)
        if [ $keytab_size -gt 100 ]; then
            echo -e "${GREEN}✅ Keytab appears valid (size: $keytab_size bytes)${NC}"
            break
        else
            echo -e "${YELLOW}⚠️  Keytab too small ($keytab_size bytes), waiting...${NC}"
        fi
    fi
    
    attempt=$((attempt + 1))
    echo -e "${YELLOW}Waiting for KDC files... ($attempt/$max_attempts)${NC}"
    
    # Debug: Show what files exist
    if [ $((attempt % 6)) -eq 0 ]; then  # Every 30 seconds
        echo -e "${BLUE}Debug - Contents of /kdc-data:${NC}"
        ls -la /kdc-data/ 2>/dev/null || echo "Directory not accessible"
    fi
    
    sleep 5
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "${RED}❌ Timeout waiting for KDC files${NC}"
    echo -e "${RED}Final state of /kdc-data:${NC}"
    ls -la /kdc-data/ 2>/dev/null || echo "Directory not accessible"
    exit 1
fi

# Copy files for Vault
echo -e "${BLUE}Creating Vault Kerberos directories...${NC}"
mkdir -p /vault-kerberos/keytabs
mkdir -p /vault-kerberos

# Copy keytab
echo -e "${BLUE}Copying keytab file...${NC}"
cp /kdc-data/vault.keytab /vault-kerberos/keytabs/vault.keytab
cp /kdc-data/vault.keytab /vault-kerberos/vault.keytab  # Also copy to root level for compatibility

# Copy config
echo -e "${BLUE}Copying krb5.conf...${NC}"
cp /kdc-data/krb5.conf /vault-kerberos/krb5.conf

# Set permissions
chmod 644 /vault-kerberos/keytabs/vault.keytab /vault-kerberos/vault.keytab /vault-kerberos/krb5.conf

# Verify the copy worked
echo -e "${BLUE}Verifying copied files:${NC}"
ls -la /vault-kerberos/
ls -la /vault-kerberos/keytabs/

echo -e "${GREEN}🎉 Files ready for Vault!${NC}"
echo -e "${BLUE}Keytab locations:${NC}"
echo -e "${BLUE}  - /vault/kerberos/keytabs/vault.keytab${NC}"
echo -e "${BLUE}  - /vault/kerberos/vault.keytab${NC}"
echo -e "${BLUE}Config: /vault/kerberos/krb5.conf${NC}"