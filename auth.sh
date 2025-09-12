vault auth enable -path=kerberos kerberos

# Extract keytab content as base64
KEYTAB_B64=$(docker-compose exec vault base64 -w 0 /vault/kerberos/vault.keytab)

# Extract krb5.conf content
KRB5_CONF=$(docker-compose exec vault cat /vault/kerberos/krb5.conf)

# Configure with base64 keytab
vault write auth/kerberos/config \
    keytab="$KEYTAB_B64" \
    service_account="vault/vault.example.com@EXAMPLE.COM" \
    realm="EXAMPLE.COM" \
    kdc="kdc.example.com:88" \
    kerberos_config="$KRB5_CONF"