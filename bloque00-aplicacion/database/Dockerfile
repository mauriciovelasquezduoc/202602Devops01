FROM postgres:16-alpine

# Variables de entorno para PostgreSQL
ENV POSTGRES_DB=ep03
ENV POSTGRES_USER=ep03_user
ENV POSTGRES_PASSWORD=ep03_pass

# Script de inicialización — se ejecuta automáticamente al primer arranque
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

EXPOSE 5432
