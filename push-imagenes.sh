#!/bin/bash
set -euo pipefail

# =====================================================
# Script: push-imagenes.sh
# Red de seguridad del laboratorio: construye y sube a
# ECR las 3 imágenes (database, backend, frontend) para
# que los pods dejen de estar en ImagePullBackOff.
#
# Dónde ejecutarlo:
#   - macOS (Docker Desktop corriendo), desde la carpeta
#     raiz del laboratorio. El contenedor del lab solo
#     tiene el cliente docker, no el daemon.
#
# Requisitos:
#   - docker corriendo
#   - credenciales vigentes en secrets.txt (academy)
#   - aws CLI y kubectl instalados
#
# Luego de subir las imagenes, reinicia los deployments
# para que los pods intenten hacer pull de inmediato.
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.txt"

# ---------- Cargar credenciales ----------
if [ -f "$SECRETS_FILE" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="${key//[[:space:]]/}"
    [ -z "$key" ] && continue
    [[ "$key" == \#* ]] && continue
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    [ -z "$value" ] && continue
    export "$key=$value"
  done < "$SECRETS_FILE"

  [ -n "${aws_access_key_id:-}" ]     && export AWS_ACCESS_KEY_ID="$aws_access_key_id"
  [ -n "${aws_secret_access_key:-}" ] && export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
  [ -n "${aws_session_token:-}" ]     && export AWS_SESSION_TOKEN="$aws_session_token"
  [ -n "${AWS_REGION:-}" ]            && export AWS_DEFAULT_REGION="$AWS_REGION"
else
  echo "ERROR: no encontré secrets.txt en $SCRIPT_DIR"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

# ---------- Validar sesión AWS ----------
echo "Validando credenciales AWS..."
if ! aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
  echo "ERROR: las credenciales de secrets.txt no son válidas (token de sesión expirado?)."
  echo "  Genera credenciales frescas en AWS Academy (AWS Details > AWS CLI) y actualiza secrets.txt."
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "OK: cuenta ${ACCOUNT_ID}, region ${REGION}"

# ---------- Verificar docker ----------
if ! command -v docker &> /dev/null; then
  echo "ERROR: docker no está instalado. Ejecuta este script en macOS con Docker Desktop."
  exit 1
fi
if ! docker info > /dev/null 2>&1; then
  echo "ERROR: el daemon de docker no está corriendo. Abre Docker Desktop e intenta de nuevo."
  exit 1
fi

# Nodos EKS son x86_64 (AL2): siempre construir linux/amd64
PLATFORM="linux/amd64"
APP_DIR="${SCRIPT_DIR}/bloque00-aplicacion"

build_and_push() {
  local name="$1" ctx="$2"
  echo ""
  echo "=== ${name} ==="
  echo "  Build (${PLATFORM})..."
  docker build --platform "$PLATFORM" -t "${name}:latest" "$ctx"
  echo "  Tag + push a ECR..."
  docker tag "${name}:latest" "${ECR_URL}/${name}:latest"
  docker push "${ECR_URL}/${name}:latest"
  echo "  OK: ${ECR_URL}/${name}:latest"
}

# ---------- Login a ECR ----------
echo ""
echo "Login a ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_URL"

# ---------- Build + push de las 3 imágenes ----------
# Orden: database primero, luego backend, luego frontend
build_and_push "ep02-database" "${APP_DIR}/ep02_ing_devops_database"
build_and_push "ep02-backend"  "${APP_DIR}/ep02_ing_devops_backend"
build_and_push "ep02-frontend" "${APP_DIR}/ep02_ing_devops_frontend"

# ---------- Verificar en ECR ----------
echo ""
echo "Imágenes disponibles en ECR:"
for repo in ep02-database ep02-backend ep02-frontend; do
  TAGS=$(aws ecr describe-images --repository-name "$repo" --region "$REGION" \
    --query 'imageDetails[].imageTags[]' --output text 2>/dev/null | tr '\t' ' ')
  echo "  ${repo}: ${TAGS:-SIN IMÁGENES}"
done

# ---------- Refrescar kubeconfig y reiniciar pods ----------
echo ""
echo "Reiniciando deployments para forzar el pull..."
if aws eks update-kubeconfig --region "$REGION" --name laboratorio-ep02-eks > /dev/null 2>&1 \
   && kubectl get namespace ep02 > /dev/null 2>&1; then
  kubectl rollout restart deployment/ep02-database -n ep02 || true
  kubectl rollout restart deployment/ep02-backend  -n ep02 || true
  kubectl rollout restart deployment/ep02-frontend -n ep02 || true
  echo ""
  echo "Estado de los pods (espera ~2-3 min a que estén Ready):"
  kubectl get pods -n ep02
else
  echo "(no pude reiniciar los deployments desde aquí; dentro del contenedor corre:)"
  echo "  kubectl rollout restart deployment/ep02-database deployment/ep02-backend deployment/ep02-frontend -n ep02"
fi

echo ""
echo "=== Listo. Verifica con: kubectl get pods -n ep02 ==="
