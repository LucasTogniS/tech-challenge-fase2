# Estimativa de custos — Fase 2

Preços on-demand da região us-east-1 (Norte da Virgínia), em dólares. A arquitetura é a descrita
em [01-arquitetura.md](01-arquitetura.md).

| Componente | Configuração | US$/hora | US$/mês (730 h) |
|---|---|---:|---:|
| EKS — plano de controle | 1 cluster, suporte padrão | 0,1000 | 73,00 |
| EC2 — nós do EKS | 2× t3.medium | 0,0832 | 60,74 |
| EBS — disco dos nós | 2× 20 GB gp3 | 0,0044 | 3,20 |
| RDS PostgreSQL | 3× db.t3.micro, Single-AZ | 0,0540 | 39,42 |
| RDS — armazenamento | 3× 20 GB gp2 | 0,0095 | 6,90 |
| ElastiCache Redis | 1× cache.t3.micro | 0,0170 | 12,41 |
| Network Load Balancer | 1 NLB + uso mínimo | 0,0285 | 20,81 |
| IPv4 públicos | 2 nós + 2 do NLB | 0,0200 | 14,60 |
| DynamoDB | on-demand, volume de demonstração | — | < 0,10 |
| SQS | Standard, < 1 milhão de requisições | — | 0,00 |
| ECR | ≈ 0,5 GB de imagens | — | 0,05 |
| **Total** | | **≈ 0,317** | **≈ 231** |

## Leitura dos números

- **O plano de controle do EKS é o maior item** (≈ 32% do total) e não depende de carga: é o preço
  de ter o Kubernetes gerenciado. Em escala pequena ele pesa; em escala maior, dilui.
- **Três RDS em vez de um**: o isolamento por serviço custa ≈ US$ 30/mês a mais do que uma única
  instância com três bancos. É o preço de cada serviço poder evoluir e escalar seu banco de forma
  independente.
- **Sem NAT Gateway** (≈ US$ 33/mês + tráfego): os nós ficam em subnets públicas e baixam as
  imagens do ECR direto pela internet.
- **Suporte padrão do EKS**: uma versão do Kubernetes fora do suporte padrão passa ao suporte
  estendido, que custa US$ 0,60/hora — seis vezes mais. O cluster deve ser criado na versão padrão
  sugerida pelo console.

## Custo no AWS Academy

Com US$ 50 de crédito para o curso inteiro, o ambiente completo não pode ficar ligado: um dia
inteiro custa ≈ US$ 7,60. A estratégia adotada:

1. Validar tudo localmente (Docker Compose e kind) antes de criar qualquer recurso.
2. Criar a infraestrutura, demonstrar e gravar, e destruir **no mesmo dia**, por script
   (`scripts/aws/99-destruir.sh`).

Uma sessão de 4 horas custa ≈ **US$ 1,30**.
