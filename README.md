# ToggleMaster — Tech Challenge Fase 2

Evolução do ToggleMaster de monolito para **5 microsserviços** conteinerizados, com orquestração
em Kubernetes (AWS EKS).

**Participantes:** Lucas de Togni Souza (RM375772) · Rafael Gamba Ramos (RM373722)

## Microsserviços

| Serviço | Linguagem | Porta | Depende de |
|---|---|---|---|
| `auth-service` | Go | 8001 | PostgreSQL (`auth_db`) |
| `flag-service` | Python | 8002 | PostgreSQL (`flag_db`), auth-service |
| `targeting-service` | Python | 8003 | PostgreSQL (`targeting_db`), auth-service |
| `evaluation-service` | Go | 8004 | Redis, flag-service, targeting-service, SQS |
| `analytics-service` | Python | 8005 | SQS, DynamoDB |

Código-fonte original: [github.com/FIAP-TCs](https://github.com/FIAP-TCs).

## Ambiente local

```bash
cp .env.example .env        # ajuste as senhas/chaves
docker compose up -d --build
```

Sobe **9 contêineres**: os 5 serviços + 2 PostgreSQL + Redis + DynamoDB Local.

| Contêiner | Papel |
|---|---|
| `postgres-auth` | Banco do auth-service |
| `postgres-flags` | Uma instância com dois bancos isolados: `flag_db` e `targeting_db` |
| `redis` | Cache do evaluation-service |
| `dynamodb` | DynamoDB Local para o analytics-service |

Para exercitar também o fluxo assíncrono (evaluation → fila → analytics → DynamoDB), suba com a
fila local compatível com SQS (ElasticMQ):

```bash
docker compose --profile fila up -d --build
```

### Teste rápido

```bash
curl http://localhost:8004/health
```

```bash
curl "http://localhost:8004/evaluate?user_id=user-1&flag_name=enable-new-dashboard"
```

A chave de serviço do evaluation-service (`SERVICE_API_KEY` no `.env`) é cadastrada
automaticamente no banco do auth-service na primeira subida. Para criar chaves de uso manual:

```bash
curl -X POST http://localhost:8001/admin/keys -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" -d '{"name":"minha-chave"}'
```

## Kubernetes

```
k8s/
├── base/                 # manifestos comuns, um diretório (e um namespace) por serviço
│   └── <serviço>/        # namespace, configmap, secret, deployment, service, ingress
│                         # + hpa (evaluation, analytics) + job de migração (serviços com PostgreSQL)
└── overlays/
    ├── aws/              # imagens do ECR; secrets com endpoints de RDS, ElastiCache e SQS
    └── kind/             # imagens locais + PostgreSQL, Redis, DynamoDB Local e ElasticMQ no cluster
```

| Serviço | Namespace | Rota no Ingress | Réplicas |
|---|---|---|---|
| auth-service | `togglemaster-auth` | `/auth/*` (prefixo removido) | 2 |
| flag-service | `togglemaster-flag` | `/flags` | 2 |
| targeting-service | `togglemaster-targeting` | `/rules` | 2 |
| evaluation-service | `togglemaster-evaluation` | `/evaluate` | HPA 1–6 (CPU 70%) |
| analytics-service | `togglemaster-analytics` | `/analytics/*` (prefixo removido) | HPA 1–4 (CPU 70%) |

Todos os Deployments têm requests/limits, readiness e liveness probe em `/health`, e rodam como
não-root com filesystem e capabilities restritos. O schema dos bancos é aplicado por um **Job**
separado, e não no boot da aplicação: é a correção do débito do fator XII apontado na Fase 1.

### Teste local com kind

O mesmo conjunto de manifestos roda num cluster local (kind, 1 control-plane + 2 workers) antes
de ir para o EKS:

```bash
./scripts/kind-up.sh
```

```bash
curl http://localhost:8080/auth/health
```

Teste de carga (`hey -z 90s -c 50` em `/evaluate`): o HPA do evaluation-service escalou de 1
para 6 pods, e o do analytics-service de 1 para 4, puxado pelo volume de eventos na fila.

Para remover o cluster local:

```bash
kind delete cluster --name togglemaster-fase2
```

## Imagens

Todas as imagens usam **multi-stage build** e rodam como usuário não-root.

| Serviço | Base de runtime | Tamanho |
|---|---|---|
| auth-service | `distroless/static` | ≈ 17 MB |
| evaluation-service | `distroless/static` | ≈ 23 MB |
| flag-service / targeting-service | `python:3.11-slim` | ≈ 211 MB |
| analytics-service | `python:3.11-slim` | ≈ 241 MB (boto3) |

## Correções no código-fonte original

O código fornecido não compilava/rodava como estava. Ajustes mínimos aplicados:

| Serviço | Problema | Correção |
|---|---|---|
| auth-service | `go.mod` declarava `pgx/v4/stdlib` como módulo próprio (versão inválida) | Removida a linha; é um pacote do módulo `pgx/v4` |
| auth-service | Imports não usados (`fmt`, `crypto/sha256`, `encoding/hex`) e driver `pgx` importado sem `_` | Imports corrigidos; `go.sum` gerado |
| evaluation-service | `os` usado sem import; `context` importado sem uso | Imports corrigidos; `go.sum` completado |
| evaluation-service | SDK v1 da AWS não aceita endpoint alternativo por variável | `AWS_SQS_ENDPOINT` opcional (vazio = SQS da AWS) |
| serviços Python | Flask 2.2.2 quebra com Werkzeug 3.x; gunicorn 20.1.0 depende de `pkg_resources` | `Werkzeug==2.2.3` fixado; gunicorn 23.0.0 |
| imagens Go | `USER nonroot` (nome) impede o Kubernetes de validar `runAsNonRoot` | `USER 65532:65532` |
| analytics-service | boto3 1.26 não lê `AWS_ENDPOINT_URL_*` (necessário para o DynamoDB Local) | boto3 1.34.162 |
