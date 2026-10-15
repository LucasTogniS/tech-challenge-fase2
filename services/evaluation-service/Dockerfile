# syntax=docker/dockerfile:1

# ---- Estágio 1: build ----
FROM golang:1.22-alpine AS build
WORKDIR /src

# Dependências primeiro: esta camada só é refeita quando go.mod/go.sum mudam
COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
# Binário estático (sem CGO), sem tabela de símbolos nem debug info
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/evaluation-service .

# ---- Estágio 2: runtime ----
# distroless/static: sem shell nem gerenciador de pacotes, roda como usuário não-root
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/evaluation-service /evaluation-service
ENV PORT=8004
EXPOSE 8004
USER nonroot:nonroot
ENTRYPOINT ["/evaluation-service"]
