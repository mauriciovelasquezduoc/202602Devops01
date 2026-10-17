# ── Etapa 1: Build ────────────────────────────────────────────────────────────
# Usamos la imagen oficial de Gradle con JDK 21 (LTS disponible en Docker Hub)
# El proyecto compila con Java 25 localmente, pero 21 es suficiente para CI/CD
FROM gradle:8.13.0-jdk21 AS build

WORKDIR /app

# Copiamos primero solo los archivos de dependencias para aprovechar el cache de capas
COPY build.gradle settings.gradle gradle.properties ./
COPY gradle ./gradle
# Configuración de análisis estático (Checkstyle, PMD, SpotBugs)
COPY config ./config

# Descargamos dependencias (cacheadas si build.gradle no cambia)
RUN gradle dependencies --no-daemon || true

# Copiamos el resto del código fuente
COPY src ./src

# Compilamos y empaquetamos sin correr tests (los tests corren en CI)
RUN gradle clean bootJar -x test --no-daemon

# ── Etapa 2: Runtime ──────────────────────────────────────────────────────────
# Alpine es la imagen oficial más pequeña de Temurin (~180 MB vs ~260 MB de
# Ubuntu/Jammy): misma JVM 21, menos disco y menos paquetes (menor superficie
# de CVEs para Trivy). Existe para amd64 y arm64 (Mac M1/M2 y CI).
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Aplicar parches de seguridad del sistema operativo (Trivy falla si la base
# trae CVEs HIGH/CRITICAL con fix disponible; apk upgrade los corrige).
# curl es necesario para el HEALTHCHECK.
RUN apk --no-cache upgrade && apk --no-cache add curl

# Usuario no-root por seguridad (sintaxis Alpine: addgroup/adduser)
RUN addgroup -S appgroup && adduser -S -G appgroup appuser

# Copiamos el jar generado
COPY --from=build /app/build/libs/ep02-app-1.0.0.jar app.jar

RUN chown appuser:appgroup app.jar

USER appuser

# Puerto expuesto
EXPOSE 8080

# Healthcheck para Docker y orquestadores
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Memoria: sin límite de contenedor, la JVM toma ~25% de la RAM del host como
# heap máximo (en una máquina de 8 GB reserva ~2 GB). Con Xms/Xmx fijos el heap
# arranca en 64 MB y nunca supera 256 MB. SerialGC es el recolector con menor
# overhead (recomendado en contenedores pequeños) y ExitOnOutOfMemoryError hace
# que el contenedor muera (y `restart` lo reviva) en vez de quedar colgado.
ENTRYPOINT ["java", "-Xms64m", "-Xmx256m", "-XX:+UseSerialGC", "-XX:+ExitOnOutOfMemoryError", "-jar", "app.jar"]
