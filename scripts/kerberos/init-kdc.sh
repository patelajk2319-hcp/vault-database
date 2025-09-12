#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Starting Kerberos KDC initialization...${NC}"
echo -e "${BLUE}========================================${NC}"

# CREATE CONFIG IN WRITABLE LOCATION - NOT /etc/krb5.conf
echo -e "${BLUE}Creating krb5.conf configuration...${NC}"
mkdir -p /tmp/krb5
cat > /tmp/krb5/krb5.conf << 'EOF'
[libdefaults]
    default_realm = EXAMPLE.COM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    EXAMPLE.COM = {
        kdc = kdc.example.com:88
        admin_server = kdc.example.com:749
        default_domain = example.com
    }

[domain_realm]
    .example.com = EXAMPLE.COM
    example.com = EXAMPLE.COM
EOF

# Use KRB5_CONFIG to point to our config
export KRB5_CONFIG=/tmp/krb5/krb5.conf
echo -e "${GREEN}✅ krb5.conf created in /tmp/krb5${NC}"

# CREATE OTHER CONFIG FILES
echo -e "${BLUE}Creating kdc.conf...${NC}"
cat > /tmp/krb5/kdc.conf << 'EOF'
[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    EXAMPLE.COM = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = FILE:/var/lib/krb5kdc/kadm5.keytab
        acl_file = /var/lib/krb5kdc/kadm5.acl
        key_stash_file = /var/lib/krb5kdc/stash
        kdc_ports = 88
        kdc_tcp_ports = 88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = aes256-cts
        supported_enctypes = aes256-cts:normal aes128-cts:normal des3-hmac-sha1:normal arcfour-hmac:normal
        default_principal_flags = +preauth
    }
EOF

echo -e "${BLUE}Creating kadm5.acl...${NC}"
cat > /tmp/krb5/kadm5.acl << 'EOF'
*/admin@EXAMPLE.COM    *
EOF
echo -e "${GREEN}✅ Configuration files created${NC}"

# INSTALL PACKAGES
echo -e "${BLUE}Updating package lists...${NC}"
apt-get update -y

export DEBIAN_FRONTEND=noninteractive

echo -e "${BLUE}Pre-configuring Kerberos...${NC}"
echo "krb5-config krb5-config/default_realm string EXAMPLE.COM" | debconf-set-selections
echo "krb5-config krb5-config/kerberos_servers string kdc.example.com" | debconf-set-selections
echo "krb5-config krb5-config/admin_server string kdc.example.com" | debconf-set-selections

echo -e "${BLUE}Installing Kerberos packages...${NC}"
apt-get install -y --no-install-recommends krb5-config krb5-user krb5-kdc krb5-admin-server
echo -e "${GREEN}✅ Packages installed${NC}"

# CREATE DIRECTORIES AND COPY CONFIGS
echo -e "${BLUE}Setting up directories and configs...${NC}"
mkdir -p /var/lib/krb5kdc /var/log/krb5 /etc/krb5kdc
chmod 755 /var/lib/krb5kdc /var/log/krb5 /etc/krb5kdc

# Copy configs to proper locations - FIXED: Copy ALL files to correct locations
cp /tmp/krb5/kdc.conf /etc/krb5kdc/kdc.conf
cp /tmp/krb5/kadm5.acl /etc/krb5kdc/kadm5.acl
# CRITICAL FIX: Also copy kadm5.acl to /var/lib/krb5kdc/ where kadmind expects it
cp /tmp/krb5/kadm5.acl /var/lib/krb5kdc/kadm5.acl
chmod 644 /etc/krb5kdc/kdc.conf /etc/krb5kdc/kadm5.acl /var/lib/krb5kdc/kadm5.acl
echo -e "${GREEN}✅ Directories and configs ready${NC}"

# CLEAN UP ANY EXISTING DATABASE IF CORRUPTED
if [ -f /var/lib/krb5kdc/principal ]; then
    echo -e "${YELLOW}⚠️ Existing database found - checking integrity...${NC}"
    # Try to read the database
    if ! /usr/sbin/kdb5_util dump /tmp/test_dump 2>/dev/null; then
        echo -e "${RED}Database corrupted - removing and recreating...${NC}"
        rm -f /var/lib/krb5kdc/principal*
        rm -f /var/lib/krb5kdc/stash*
        rm -f /var/lib/krb5kdc/.k5.*
    else
        echo -e "${GREEN}Database appears intact${NC}"
        rm -f /tmp/test_dump
    fi
fi

# CREATE DATABASE - FIXED: Use -P flag to avoid interactive prompt
if [ ! -f /var/lib/krb5kdc/principal ]; then
    echo -e "${BLUE}Creating KDC database...${NC}"
    # Use -P flag to specify password directly (no interactive prompt)
    /usr/sbin/kdb5_util create -s -r EXAMPLE.COM -P masterkey123
    echo -e "${GREEN}✅ Database created${NC}"
else
    echo -e "${YELLOW}⚠️ Database exists${NC}"
fi

# VERIFY STASH FILE EXISTS - FIXED: Use -P flag
if [ ! -f /var/lib/krb5kdc/stash ]; then
    echo -e "${RED}⚠️ Stash file missing! Creating...${NC}"
    /usr/sbin/kdb5_util stash -f /var/lib/krb5kdc/stash -P masterkey123
fi

# Set proper permissions on database files
chmod 600 /var/lib/krb5kdc/principal* 2>/dev/null || true
chmod 600 /var/lib/krb5kdc/stash 2>/dev/null || true

# START SERVICES WITH PROPER CONFIG
echo -e "${BLUE}Starting services...${NC}"

# Kill any existing processes first
pkill -f krb5kdc || true
pkill -f kadmind || true
sleep 2

# Start KDC with explicit config file
/usr/sbin/krb5kdc -P /var/run/krb5kdc.pid -n &
KDC_PID=$!
sleep 3

# Verify KDC started successfully
if ! kill -0 $KDC_PID 2>/dev/null; then
    echo -e "${RED}⚠️ KDC failed to start! Checking logs...${NC}"
    cat /var/log/krb5kdc.log 2>/dev/null || echo "No KDC log found"
    exit 1
fi

# VERIFY ACL FILE EXISTS BEFORE STARTING KADMIN
echo -e "${BLUE}Verifying ACL file exists...${NC}"
if [ ! -f /var/lib/krb5kdc/kadm5.acl ]; then
    echo -e "${RED}⚠️ ACL file missing! Creating...${NC}"
    cp /tmp/krb5/kadm5.acl /var/lib/krb5kdc/kadm5.acl
    chmod 644 /var/lib/krb5kdc/kadm5.acl
fi
echo -e "${GREEN}✅ ACL file verified at /var/lib/krb5kdc/kadm5.acl${NC}"

# Start kadmin server
/usr/sbin/kadmind -P /var/run/kadmind.pid -nofork &
KADMIN_PID=$!
sleep 3

# Verify kadmin started successfully
if ! kill -0 $KADMIN_PID 2>/dev/null; then
    echo -e "${RED}⚠️ Kadmin failed to start! Checking logs...${NC}"
    echo "Contents of /var/lib/krb5kdc:"
    ls -la /var/lib/krb5kdc/
    cat /var/log/kadmin.log 2>/dev/null || echo "No kadmin log found"
    exit 1
fi

echo -e "${GREEN}✅ Services started (KDC: $KDC_PID, Kadmin: $KADMIN_PID)${NC}"

# Wait a bit more for services to be fully ready
sleep 5

# CREATE PRINCIPALS
echo -e "${BLUE}Creating principals...${NC}"

# Create admin principal first
if ! /usr/sbin/kadmin.local -q "getprinc admin/admin@EXAMPLE.COM" 2>/dev/null | grep -q "Principal:"; then
    /usr/sbin/kadmin.local -q "addprinc -pw admin123 admin/admin@EXAMPLE.COM"
    echo -e "${GREEN}✅ Admin principal created${NC}"
else
    echo -e "${YELLOW}Admin exists${NC}"
fi

# Create vault service principal
if ! /usr/sbin/kadmin.local -q "getprinc vault/vault.example.com@EXAMPLE.COM" 2>/dev/null | grep -q "Principal:"; then
    /usr/sbin/kadmin.local -q "addprinc -randkey vault/vault.example.com@EXAMPLE.COM"
    echo -e "${GREEN}✅ Vault service principal created${NC}"
else
    echo -e "${YELLOW}Vault service principal exists${NC}"
fi

# Create test user
if ! /usr/sbin/kadmin.local -q "getprinc testuser@EXAMPLE.COM" 2>/dev/null | grep -q "Principal:"; then
    /usr/sbin/kadmin.local -q "addprinc -pw user123 testuser@EXAMPLE.COM"
    echo -e "${GREEN}✅ Test user created${NC}"
else
    echo -e "${YELLOW}Test user exists${NC}"
fi

echo -e "${GREEN}✅ Principals created${NC}"

# GENERATE KEYTAB
echo -e "${BLUE}Generating keytab...${NC}"
/usr/sbin/kadmin.local -q "ktadd -k /var/lib/krb5kdc/vault.keytab vault/vault.example.com@EXAMPLE.COM"
chmod 644 /var/lib/krb5kdc/vault.keytab
echo -e "${GREEN}✅ Keytab generated${NC}"

# COPY CONFIG FOR EXTERNAL ACCESS
cp /tmp/krb5/krb5.conf /var/lib/krb5kdc/krb5.conf
chmod 644 /var/lib/krb5kdc/krb5.conf

# TEST THE SETUP
echo -e "${BLUE}Testing KDC setup...${NC}"
if printf "admin123\n" | /usr/bin/kinit admin/admin@EXAMPLE.COM 2>/dev/null; then
    echo -e "${GREEN}✅ Authentication test passed${NC}"
    /usr/bin/klist | head -5
    /usr/bin/kdestroy
else
    echo -e "${RED}⚠️ Authentication test failed${NC}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}🎉 KDC INITIALIZATION COMPLETE! 🎉${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Ready for Vault integration!${NC}"
echo ""

# Show final status
echo -e "${BLUE}Final Status:${NC}"
echo "KDC PID: $KDC_PID"
echo "Kadmin PID: $KADMIN_PID"
echo "Principals:"
/usr/sbin/kadmin.local -q "listprincs" | head -10

# Show file locations for debugging
echo -e "${BLUE}File locations:${NC}"
echo "ACL file: /var/lib/krb5kdc/kadm5.acl"
echo "Keytab: /var/lib/krb5kdc/vault.keytab"
echo "Config: /var/lib/krb5kdc/krb5.conf"
ls -la /var/lib/krb5kdc/

# Keep services running
wait