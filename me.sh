vault policy write kerberos-users - << EOF
path "auth/token/lookup-self" {
    capabilities = ["read"]
}

path "auth/token/renew-self" {
    capabilities = ["update"]
}

path "auth/token/revoke-self" {
    capabilities = ["update"]
}

path "sys/capabilities-self" {
    capabilities = ["update"]
}

path "identity/entity/id/{{identity.entity.id}}" {
    capabilities = ["read"]
}

path "secret/data/myapp/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/myapp" {
    capabilities = ["list"]
}
EOF

vault write auth/kerberos/role/testuser \
    bound_service_account_names="testuser@EXAMPLE.COM" \
    token_policies="kerberos-users" \
    token_ttl=1h \
    token_max_ttl=4h