docker-compose exec kerberos-client bash -c "
    apt-get update -y > /dev/null 2>&1 &&
    apt-get install -y curl gpg > /dev/null 2>&1 &&
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg &&
    echo 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com focal main' > /etc/apt/sources.list.d/hashicorp.list &&
    apt-get update -y > /dev/null 2>&1 &&
    apt-get install -y vault > /dev/null 2>&1 &&
    echo 'Vault CLI installed successfully'
"