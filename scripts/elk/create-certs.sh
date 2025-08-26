#!/bin/bash

# Summary of what this script accomplishes:
# 1. Creates a Certificate Authority (CA) that acts as a trusted root
# 2. Generates TLS certificates for Elasticsearch and Kibana signed by the CA  
# 3. Configures certificates with proper Subject Alternative Names for flexible hostname/IP usage
# 4. Sets secure file permissions to protect private keys
# 5. Cleans up temporary files for a tidy final result
#
# The resulting certificates enable encrypted TLS communication between:
# - Clients and Elasticsearch
# - Clients and Kibana  
# - Elasticsearch and Kibana


# Define color codes for colored terminal output
GREEN='\033[0;32m'    # Green text for success messages
YELLOW='\033[1;33m'   # Yellow text for warnings
BLUE='\033[0;34m'     # Blue text for informational messages
NC='\033[0m'          # No Color - resets text color to default

# Configuration variables
CERT_VALIDITY_DAYS=365  # Certificates will be valid for 1 year
CERT_KEY_SIZE=4096      # RSA key size (4096 bits for strong security)

# Step 1: Create directory structure for organizing certificates
echo -e "${BLUE}📁 Creating Certificate Directory Structure${NC}"
# Create nested directories: certs/ca, certs/elasticsearch, certs/kibana
mkdir -p certs/{ca,elasticsearch,kibana}
echo -e "${GREEN}✅ Certificate directories created${NC}"

echo ""
echo -e "${BLUE}🔐 Generating Certificate Authority (CA)${NC}"

# Generate CA private key (4096-bit RSA)
# This key will be used to sign all other certificates
openssl genrsa -out certs/ca/ca.key $CERT_KEY_SIZE

# Create self-signed CA certificate
# -new: create new certificate request
# -x509: output self-signed certificate instead of certificate request
# -days: certificate validity period
# -subj: certificate subject information (Country, State, Location, Organization, etc.)
openssl req -new -x509 -days $CERT_VALIDITY_DAYS -key certs/ca/ca.key -out certs/ca/ca.crt \
    -subj "/C=US/ST=CA/L=San Francisco/O=Elastic/OU=IT/CN=Elastic-Certificate-Authority"
echo -e "${GREEN}✅ CA certificate created${NC}"

echo ""
echo -e "${BLUE}🔐 Generating Elasticsearch Certificate${NC}"

# Generate Elasticsearch private key
openssl genrsa -out certs/elasticsearch/elasticsearch.key $CERT_KEY_SIZE

# Create Certificate Signing Request (CSR) for Elasticsearch
# CSR contains the public key and identifying information
openssl req -new -key certs/elasticsearch/elasticsearch.key \
    -out certs/elasticsearch/elasticsearch.csr \
    -subj "/C=US/ST=CA/L=San Francisco/O=Elastic/OU=IT/CN=elasticsearch"

# Create extension file for Elasticsearch certificate
# This defines additional certificate properties and Subject Alternative Names (SANs)
cat > certs/elasticsearch/elasticsearch.ext << EOF
authorityKeyIdentifier=keyid,issuer          # Links cert to CA that signed it
basicConstraints=CA:FALSE                    # This is not a CA certificate
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment  # Allowed key uses
extendedKeyUsage = serverAuth, clientAuth    # Certificate can be used for server and client authentication
subjectAltName = @alt_names                  # Reference to alternative names section

[alt_names]
DNS.1 = elasticsearch    # Allow connections to "elasticsearch" hostname
DNS.2 = localhost       # Allow connections to "localhost"
IP.1 = 127.0.0.1       # Allow connections to local IP address
EOF

# Sign the Elasticsearch CSR with the CA to create the final certificate
# -CAcreateserial: create CA serial number file if it doesn't exist
# -extfile: use extension file for additional certificate properties
openssl x509 -req -in certs/elasticsearch/elasticsearch.csr \
    -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial \
    -out certs/elasticsearch/elasticsearch.crt -days $CERT_VALIDITY_DAYS \
    -extfile certs/elasticsearch/elasticsearch.ext

echo -e "${GREEN}✅ Elasticsearch certificate created${NC}"

echo ""
echo -e "${BLUE}🔐 Generating Kibana Certificate${NC}"

# Generate Kibana private key (same process as Elasticsearch)
openssl genrsa -out certs/kibana/kibana.key $CERT_KEY_SIZE

# Create Certificate Signing Request (CSR) for Kibana
openssl req -new -key certs/kibana/kibana.key \
    -out certs/kibana/kibana.csr \
    -subj "/C=US/ST=CA/L=San Francisco/O=Elastic/OU=IT/CN=kibana"

# Create extension file for Kibana certificate
# Same configuration as Elasticsearch but for Kibana service
cat > certs/kibana/kibana.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kibana      # Allow connections to "kibana" hostname  
DNS.2 = localhost   # Allow connections to "localhost"
IP.1 = 127.0.0.1   # Allow connections to local IP address
EOF

# Sign the Kibana CSR with the CA to create the final certificate
openssl x509 -req -in certs/kibana/kibana.csr \
    -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial \
    -out certs/kibana/kibana.crt -days $CERT_VALIDITY_DAYS \
    -extfile certs/kibana/kibana.ext

echo -e "${GREEN}✅ Kibana certificate created${NC}"

echo ""
echo -e "${BLUE}🧹 Cleaning up temporary files${NC}"

# Remove temporary files that are no longer needed
# CSR files: only needed during certificate creation
# Extension files: only needed during signing process  
# Serial file: automatically created, not needed to keep
rm -f certs/elasticsearch/elasticsearch.csr certs/elasticsearch/elasticsearch.ext
rm -f certs/kibana/kibana.csr certs/kibana/kibana.ext
rm -f certs/ca/ca.srl

echo ""
echo -e "${BLUE}🔒 Setting proper file permissions${NC}"
# Set directory permissions (755 = read/write/execute for owner, read/execute for group/others)
chmod 755 certs certs/{ca,elasticsearch,kibana}

# Set certificate file permissions (644 = read/write for owner, read-only for group/others)
# Certificates are public and can be readable by others
chmod 644 certs/ca/ca.crt certs/elasticsearch/elasticsearch.crt certs/kibana/kibana.crt

# Set private key permissions (600 = read/write for owner only)
# Private keys must be kept secret and accessible only to the owner
chmod 600 certs/ca/ca.key certs/elasticsearch/elasticsearch.key certs/kibana/kibana.key

echo ""
echo -e "${GREEN}🎉 Certificate generation completed!${NC}"
echo ""
echo "Generated certificates:"
echo "  📁 CA: certs/ca/ca.crt (valid for $CERT_VALIDITY_DAYS days)"
echo "  📁 Elasticsearch: certs/elasticsearch/elasticsearch.crt"
echo "  📁 Kibana: certs/kibana/kibana.crt"

