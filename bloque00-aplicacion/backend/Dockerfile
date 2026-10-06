# ── Etapa 1: Build ────────────────────────────────────────────────────────────
# Usamos la imagen oficial de Gradle con JDK 21 (LTS disponible en Docker Hub)
# El proyecto compila con Java 25 localmente, pero 21 es suficiente para CI/CD
FROM gradle:8.13.0-jdk21 AS build

WORKDIR /app

# Copiamos primero solo los archivos de dependencias para aprovechar el cache de capas
COPY build.gradle settings.gradle gradle.properties ./
COPY gradle ./gradle

# Descargamos dependencias (cacheadas si build.gradle no cambia)
RUN gradle dependencies --no-daemon || true

# Copiamos el resto del código fuente
COPY src ./src

# Compilamos y empaquetamos sin correr tests (los tests corren en CI)
RUN gradle clean bootJar -x test --no-daemon

# ── Etapa 2: Runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy

WORKDIR /app

# Usuario no-root por seguridad
RUN groupadd --system appgroup && useradd --system --gid appgroup appuser

# Copiamos el jar generado
COPY --from=build /app/build/libs/ep03-app-1.0.0.jar app.jar

RUN chown appuser:appgroup app.jar

USER appuser

# Puerto expuesto
EXPOSE 8080

# Healthcheck para Docker y orquestadores
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
