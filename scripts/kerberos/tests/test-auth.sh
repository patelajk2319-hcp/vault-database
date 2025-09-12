#!/bin/bash
# ============================================================================
# KERBEROS AUTHENTICATION TEST SCRIPT
# This script tests basic Kerberos authentication functionality
# Run this inside the kerberos-client container to verify setup
# ============================================================================

# Color definitions for output formatting
GREEN='\033[0;32m'    # Green text for success messages
YELLOW='\033[1;33m'   # Yellow text for warnings
BLUE='\033[0;34m'     # Blue text for informational messages
RED='\033[0;31m'      # Red text for error messages
NC='\033[0m'          # No Color - resets text color to default

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}🧪 KERBEROS AUTHENTICATION TEST SUITE 🧪${NC}"
echo -e "${BLUE}================================================${NC}"

# ============================================================================
# TEST 1: AUTHENTICATE AS TEST USER
# Obtain a Kerberos ticket for the test user
# ============================================================================
echo ""
echo -e "${BLUE}📝 Step 1: Authenticating as testuser@EXAMPLE.COM${NC}"
echo -e "${YELLOW}   Password: user123${NC}"
echo -e "${BLUE}   ├── Requesting TGT from KDC...${NC}"

# Use echo to pipe password to kinit (non-interactive authentication)
# kinit requests a Ticket Granting Ticket (TGT) from the KDC
echo "user123" | kinit testuser@EXAMPLE.COM 2>/dev/null

# Check if authentication was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}   └── ✓ Authentication successful!${NC}"
else
    echo -e "${RED}   └── ✗ Authentication failed!${NC}"
    echo -e "${RED}       Check KDC connectivity and credentials${NC}"
    exit 1
fi

# ============================================================================
# TEST 2: DISPLAY CURRENT TICKETS
# Show the tickets we've obtained from the KDC
# ============================================================================
echo ""
echo -e "${BLUE}📋 Step 2: Displaying current Kerberos tickets${NC}"
echo -e "${BLUE}   ┌────────────────────────────────────────────────────────────┐${NC}"

# klist shows all tickets in the current credential cache
klist 2>/dev/null | while read line; do
    echo -e "${BLUE}   │${NC} $line"
done

echo -e "${BLUE}   └────────────────────────────────────────────────────────────┘${NC}"

# ============================================================================
# TEST 3: VERIFY TICKET DETAILS
# Parse klist output to show ticket information
# ============================================================================
echo ""
echo -e "${BLUE}🔍 Step 3: Verifying ticket details${NC}"

# Check if we have a valid TGT (Ticket Granting Ticket)
TGT_COUNT=$(klist 2>/dev/null | grep "krbtgt/EXAMPLE.COM@EXAMPLE.COM" | wc -l)

if [ $TGT_COUNT -gt 0 ]; then
    echo -e "${GREEN}   ├── ✓ Valid TGT (Ticket Granting Ticket) found${NC}"
    echo -e "${BLUE}   ├── This ticket can be used to request service tickets${NC}"
    
    # Get ticket expiration
    EXPIRY=$(klist 2>/dev/null | grep "krbtgt/EXAMPLE.COM@EXAMPLE.COM" | awk '{print $3, $4}')
    echo -e "${BLUE}   └── Expires: $EXPIRY${NC}"
else
    echo -e "${RED}   └── ✗ No valid TGT found${NC}"
    echo -e "${RED}       Authentication may have failed${NC}"
fi

# ============================================================================
# TEST 4: OPTIONAL - TEST SERVICE TICKET REQUEST
# Try to get a service ticket (if service is available)
# ============================================================================
echo ""
echo -e "${BLUE}🎫 Step 4: Testing service ticket request${NC}"
echo -e "${BLUE}   ├── Attempting to get ticket for Vault service...${NC}"

# Try to get a ticket for the Vault service principal
# This simulates what Vault would do when authenticating users
kvno vault/vault.example.com@EXAMPLE.COM > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   └── ✓ Successfully obtained service ticket for Vault${NC}"
else
    echo -e "${YELLOW}   └── ⚠ Could not obtain service ticket${NC}"
    echo -e "${YELLOW}       (This is normal if Vault isn't configured yet)${NC}"
fi

# ============================================================================
# TEST 5: DISPLAY FINAL TICKET CACHE
# Show all tickets after testing
# ============================================================================
echo ""
echo -e "${BLUE}📊 Step 5: Final ticket cache status${NC}"
TICKET_COUNT=$(klist 2>/dev/null | grep -E "Valid starting|Expires" | wc -l)
echo -e "${BLUE}   ├── Total tickets in cache: $TICKET_COUNT${NC}"

if [ $TICKET_COUNT -gt 0 ]; then
    echo -e "${GREEN}   └── ✓ Ticket cache is populated${NC}"
else
    echo -e "${YELLOW}   └── ⚠ Ticket cache appears empty${NC}"
fi

# ============================================================================
# TEST COMPLETE
# Summary of test results
# ============================================================================
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}🎉 KERBEROS AUTHENTICATION TEST COMPLETE! 🎉${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

if [ $TGT_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ RESULT: SUCCESS${NC}"
    echo -e "${BLUE}   Kerberos authentication is working correctly!${NC}"
    echo -e "${BLUE}   You can now proceed to configure Vault.${NC}"
else
    echo -e "${RED}❌ RESULT: FAILED${NC}"
    echo -e "${RED}   Kerberos authentication is not working properly.${NC}"
    echo -e "${RED}   Check KDC logs and network connectivity.${NC}"
fi

echo ""
echo -e "${YELLOW}📖 Useful Commands:${NC}"
echo -e "${BLUE}   ├── Run this test again:${NC}"
echo -e "${BLUE}   │   docker-compose exec kerberos-client /test-auth.sh${NC}"
echo -e "${BLUE}   │${NC}"
echo -e "${BLUE}   ├── Clear tickets and test again:${NC}"
echo -e "${BLUE}   │   docker-compose exec kerberos-client kdestroy${NC}"
echo -e "${BLUE}   │   docker-compose exec kerberos-client /test-auth.sh${NC}"
echo -e "${BLUE}   │${NC}"
echo -e "${BLUE}   ├── View current tickets:${NC}"
echo -e "${BLUE}   │   docker-compose exec kerberos-client klist${NC}"
echo -e "${BLUE}   │${NC}"
echo -e "${BLUE}   └── Manual authentication:${NC}"
echo -e "${BLUE}       docker-compose exec kerberos-client kinit testuser@EXAMPLE.COM${NC}"
echo ""
echo -e "${BLUE}================================================${NC}"