#!/usr/bin/env bash
# Ajusta a VPC criada pelo console ("VPC and more") para o EKS:
#  - subnets públicas atribuem IP público automaticamente (os nós ficam nelas,
#    sem NAT Gateway, e precisam de IP público para baixar imagens do ECR);
#  - tags que indicam onde o Load Balancer do Ingress pode ser criado.
. "$(dirname "$0")/lib.sh"

VPC=$(vpc_id)
log "VPC $VPC_NAME ($VPC)"

PUB=$(subnets publicas); PRIV=$(subnets privadas)
[ -n "$PUB" ] && [ -n "$PRIV" ] || falha "Subnets públicas/privadas não encontradas na VPC."

for s in $PUB; do
  aws_ ec2 modify-subnet-attribute --subnet-id "$s" --map-public-ip-on-launch
  aws_ ec2 create-tags --resources "$s" --tags Key=kubernetes.io/role/elb,Value=1 "Key=kubernetes.io/cluster/$CLUSTER,Value=shared"
  ok "pública  $s: IP público automático + tag de Load Balancer"
done
for s in $PRIV; do
  aws_ ec2 create-tags --resources "$s" --tags Key=kubernetes.io/role/internal-elb,Value=1 "Key=kubernetes.io/cluster/$CLUSTER,Value=shared"
  ok "privada  $s: tag de Load Balancer interno"
done
