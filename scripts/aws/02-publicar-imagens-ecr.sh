#!/usr/bin/env bash
# Cria os 5 repositórios no ECR (se não existirem), faz o build e publica as imagens.
. "$(dirname "$0")/lib.sh"

REGISTRY=$(ecr_registry)

log "Repositórios ECR"
for s in $SERVICES; do
  repo="$ECR_NAMESPACE/$s"
  if aws_ ecr describe-repositories --repository-names "$repo" >/dev/null 2>&1; then
    ok "$repo (já existe)"
  else
    aws_ ecr create-repository --repository-name "$repo" \
      --image-scanning-configuration scanOnPush=true \
      --tags Key=Project,Value=togglemaster Key=Phase,Value=fase2 >/dev/null
    ok "$repo criado"
  fi
done

log "Login do Docker no ECR"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

log "Build das imagens (linux/amd64, mesma arquitetura dos nós t3.medium)"
(cd "$RAIZ" && DOCKER_DEFAULT_PLATFORM=linux/amd64 docker compose build $SERVICES)

log "Push (tag $IMAGE_TAG)"
for s in $SERVICES; do
  destino="$REGISTRY/$ECR_NAMESPACE/$s:$IMAGE_TAG"
  docker tag "togglemaster-fase2/$s:local" "$destino"
  docker push --quiet "$destino"
  ok "$destino"
done
