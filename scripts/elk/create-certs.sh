#!/bin/bash

echo "=== TLS Certificate Generator for Elasticsearch & Kibana ==="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CERT_VALIDITY_DAYS=365
CERT_KEY_SIZE=4096

echo -e "${BLUE}📁 Creating Certificate Directory Structure${NC}"
mkdir -p certs/{ca,elasticsearch,kibana}
echo -e "${GREEN}✅ Certificate directories created${NC}"

echo ""
echo -e "${BLUE}🔐 Generating Certificate Authority (CA)${NC}"
openssl genrsa -out certs/ca/ca.key $CERT_KEY_SIZE
openssl req -new -x509 -days $CERT_VALIDITY_DAYS -key certs/ca/ca.key -out certs/ca/ca.crt \
    -subj "/C=US/ST=CA/L=San Francisco/O=Elastic/OU=IT/CN=Elastic-Certificate-Authority"
echo -e "${GREEN}✅ CA certificate created${NC}"

echo ""
echo -e "${BLUE}🔐 Generating Elasticsearch Certificate${NC}"
openssl genrsa -out certs/elasticsearch/elasticsearch.key $CERT_KEY_SIZE
openssl req -new -key certs/elasticsearch/elasticsearch.key \
    -out certs/elasticsearch/elasticsearch.csr \
    -subj "/C=US/ST=CA/L=San Francisco/O=Elastic/OU=IT/CN=elasticsearch"

cat > certs/elasticsearch/elasticsearch.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = elasticsearch
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in certs/elasticsearch/elasticsearch.csr \
    -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial \
    -out certs/elasticsearch/elasticsearch.crt -days $CERT_VALIDITY_DAYS \
    -extfile certs/elasticsearch/elasticsearch.ext

echo -e "${GREEN}✅ Elasticsearch certificate created${NC}"

echo ""
echo -e "${BLUE}🔐 Generating Kibana Certificate${NC}"
openssl genrsa -out certs/kibana/kibana.key $CERT_KEY_SIZE
openssl req -new -key certs/kibana/kibana.key \
    -out certs/kibana/kibana.csr \
    -subj "/C=US/ST=CA/L=San Francisco/O=Elastic/OU=IT/CN=kibana"

cat > certs/kibana/kibana.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kibana
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in certs/kibana/kibana.csr \
    -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial \
    -out certs/kibana/kibana.crt -days $CERT_VALIDITY_DAYS \
    -extfile certs/kibana/kibana.ext

echo -e "${GREEN}✅ Kibana certificate created${NC}"

echo ""
echo -e "${BLUE}🧹 Cleaning up temporary files${NC}"
rm -f certs/elasticsearch/elasticsearch.csr certs/elasticsearch/elasticsearch.ext
rm -f certs/kibana/kibana.csr certs/kibana/kibana.ext
rm -f certs/ca/ca.srl

echo ""
echo -e "${BLUE}🔒 Setting proper file permissions${NC}"
chmod 755 certs certs/{ca,elasticsearch,kibana}
chmod 644 certs/ca/ca.crt certs/elasticsearch/elasticsearch.crt certs/kibana/kibana.crt
chmod 600 certs/ca/ca.key certs/elasticsearch/elasticsearch.key certs/kibana/kibana.key

echo ""
echo -e "${GREEN}🎉 Certificate generation completed!${NC}"
echo ""
echo "Generated certificates:"
echo "  📁 CA: certs/ca/ca.crt (valid for $CERT_VALIDITY_DAYS days)"
echo "  📁 Elasticsearch: certs/elasticsearch/elasticsearch.crt"
echo "  📁 Kibana: certs/kibana/kibana.crt"