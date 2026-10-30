# Relatório de Entrega — Tech Challenge Fase 2

**POSTECH DevOps e Arquitetura Cloud (DCLT)** · Projeto ToggleMaster

## Participantes

| Nome | RM | Discord |
|---|---|---|
| Lucas de Togni Souza | RM375772 | `_lucassx_` |
| Rafael Gamba Ramos | RM373722 | `rafa_217616` |

## Links

| Item | Link |
|---|---|
| Repositório | https://github.com/LucasTogniS/tech-challenge-fase2 |
| Vídeo de demonstração | https://youtu.be/PdSF5AVEZgI |

## Roteiro do vídeo (14:57)

| Início | Bloco | Narração |
|---|---|---|
| 0:00 | Abertura | Lucas |
| 0:41 | Arquitetura (diagrama) | Rafael |
| 2:42 | Ambiente local com Docker Compose (9 contêineres) | Lucas |
| 4:15 | Infraestrutura na AWS (EKS, node group, ECR, RDS, ElastiCache, DynamoDB, SQS) | Rafael |
| 6:20 | Pods, Ingress e teste pelo Load Balancer | Lucas |
| 8:13 | Escalabilidade: HPA do evaluation-service sob carga | Rafael |
| 10:09 | Fila SQS, HPA do analytics-service e dados no DynamoDB | Lucas |
| 11:51 | Por que cada escolha (RDS x ElastiCache x DynamoDB; HPA x KEDA) | Rafael |
| 13:33 | Desafios e encerramento | Lucas |

## O que foi entregue

| Requisito | Onde está |
|---|---|
| Dockerfile multi-stage para os 5 microsserviços | `services/*/Dockerfile` |
| `docker-compose.yml` com 5 apps + 2 PostgreSQL + Redis + DynamoDB Local | `docker-compose.yml` |
| Cluster EKS (console, `LabRole`) com Managed Node Group 1/2/4 | Vídeo · `docs/01-arquitetura.md` |
| 5 repositórios ECR com as imagens publicadas | `scripts/aws/02-publicar-imagens-ecr.sh` |
| 3 RDS PostgreSQL, 1 ElastiCache Redis, 1 DynamoDB, 1 SQS Standard | Vídeo · `scripts/aws/03-provisionar-recursos.sh` |
| Metrics Server e Nginx Ingress Controller | `scripts/aws/05-preparar-cluster.sh` |
| Namespace, Deployment, Service ClusterIP, Secret, ConfigMap por serviço | `k8s/base/<serviço>/` |
| Ingress com roteamento por caminho | `k8s/base/*/ingress.yaml` |
| Requests/limits, readiness e liveness probes | `k8s/base/*/deployment.yaml` |
| HPA por CPU (70%) no evaluation-service e no analytics-service | `k8s/base/{evaluation,analytics}-service/hpa.yaml` |
| Arquitetura, decisões e limitações do AWS Academy | `docs/01-arquitetura.md` |
| Diagrama de arquitetura | `diagrama/togglemaster-fase2-arquitetura.drawio(.png)` |
| Estimativa de custos | `docs/02-estimativa-custos.md` |

## Resumo

Os cinco microsserviços foram conteinerizados com imagens multi-stage e executados localmente com
Docker Compose. A infraestrutura foi provisionada na AWS (Academy) e as aplicações implantadas no
EKS, cada uma em seu namespace, expostas por um único Network Load Balancer criado pelo Nginx
Ingress Controller.

O evaluation-service e o analytics-service escalam por CPU com HPA. No analytics-service, o HPA por
CPU substitui o KEDA, inviável no Academy por exigir a criação de IAM Roles: com a fila cheia o
consumidor trabalha sem pausa e a CPU sobe, levando o HPA a adicionar réplicas.

O código-fonte recebido não compilava como estava (imports inválidos e `go.mod` com módulo
inexistente nos serviços Go, dependências incompatíveis nos serviços Python). As correções foram
mínimas e estão listadas no `README.md`.
