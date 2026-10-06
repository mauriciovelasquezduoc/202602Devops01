# ── Etapa 1: Dependencias ─────────────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install

# ── Etapa 2: Tests + Cobertura ────────────────────────────────────────────────
# Si la cobertura < 90% el build se DETIENE aquí (exit code != 0)
FROM deps AS test
COPY . .
RUN npm run test:coverage

# ── Etapa 3: Build de producción ──────────────────────────────────────────────
# Hereda de test → si los tests fallan, esta etapa nunca se ejecuta
FROM test AS build
RUN npm run build
# Sin VITE_API_URL: el frontend usa rutas relativas (/ep03)
# Nginx hace el proxy interno: /ep03 → http://backend:8080

# ── Etapa 4: Servidor estático con Nginx ──────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

# Instalar envsubst (viene en gettext)
RUN apk add --no-cache gettext

# Copiar nginx.conf como template — contiene ${BACKEND_HOST}
COPY nginx.conf /etc/nginx/conf.d/default.conf.template

COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:80 || exit 1

# Al arrancar: reemplaza ${BACKEND_HOST} con la variable de entorno real
# Ejemplo local:  docker run -e BACKEND_HOST=backend ...
# Ejemplo AWS:    docker run -e BACKEND_HOST=10.0.1.45 ...
CMD ["/bin/sh", "-c", \
  "envsubst '$BACKEND_HOST' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
