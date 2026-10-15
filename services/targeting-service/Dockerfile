# syntax=docker/dockerfile:1

# ---- Estágio 1: instala as dependências num prefixo isolado ----
FROM python:3.11-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Estágio 2: runtime ----
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8003
WORKDIR /app

COPY --from=build /install /usr/local
COPY app.py .

RUN useradd --system --uid 10001 --no-create-home app
USER 10001

EXPOSE 8003
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --access-logfile - app:app"]
