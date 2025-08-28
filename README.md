# docker-vault-redis-stack

## Description
This repository contains a docker compose stack with the following services:
- grafana
- loki
- prometheus
- promtail
- vault enterprise with raft backend
- Redis
- Elasticsearch and Kibana

## Pre-requisites

Install `Docker` with the following command:
```shell
  brew install docker
```
Install `taskfile` and `jq` with the following command:
```shell
  brew install go-task jq
```
Install `terraform` with the following command:
```shell
  brew install terraform
```

Clone git repository:
```shell
git clone https://github.com/patelajk2319-hcp/vault-database.git
```

Create a `.env` file in the root folder with the following content:
```shell
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_LICENSE=INSERT_LICENSE_HERE
```

If you do not have an enterprise license, you can request a trial license from the following link:
https://www.hashicorp.com/products/vault/trial

Alternatively, you can use the Vault BSL container image by changing the [docker-compose.yml](docker-compose.yml) file to use the `hashicorp/vault-enterprise:1.19` image.

## Usage
[Taskfile.yml](Taskfile.yml) contains automation commands to manage the stack.

Launch the docker compose stack with the following command:
```bash
task up
```

Initialise vault and unseal.
```shell
task init
task unseal
```

Add the VAULT_TOKEN to the `.env` file and load.
```shell
source .env
vault token lookup
```

## Post initialisation
```shell
source .env
task up unseal
```

Navigate to the following urls:
- http://localhost:3000/ - Grafana
- http://localhost:9090/ - Prometheus
- http://localhost:8200/ - Vault
- http://localhost:6379/ - Redis
- https://localhost:5601/ - Kibana
- https://localhost:9200/ - Elasticsearch

Execute vault benchmark to test the performance of the vault and generate vault metrics.
(requires `vault-benchmark` cli tool)
```shell
vault namespace create vault-benchmark
task benchmark
```
Execute Redis Terraform to create dynamic users, and migrate static users from Redis to Vault
```shell
task redis
```
Execute Elasticsearch Terraform to create dynamic users, and migrate static users from Elasticsearch to Vault
```shell
task elk
```
