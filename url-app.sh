#!/bin/bash
set -euo pipefail

# =====================================================
# Script: url-app.sh
# Obtiene y muestra la URL pública de la aplicación
# (Service LoadBalancer del frontend en el namespace ep02).
#
# Uso:
#   ./url-app.sh              # muestra la URL (espera a que el ELB exista)
#   ./url-app.sh --open       # además la abre en el navegador
#
# Lee credenciales de ../secrets.txt.
# Variables opcionales:
#   NAMESPACE=ep02 SERVICE=ep02-frontend REGION=us-east-1 \
#   CLUSTER_NAME=laboratorio-ep02-eks ./url-app.sh
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.txt"
# Fallback: si no está junto al script, probar en el directorio actual
if [ ! -f "$SECRETS_FILE" ] && [ -f "./secrets.txt" ]; then
  SECRETS_FILE="./secrets.txt"
fi

# Cargar credenciales de secrets.txt (para que aws/kubectl autentiquen)
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
fi

NAMESPACE="${NAMESPACE:-ep02}"
SERVICE="${SERVICE:-ep02-frontend}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"
CLUSTER_NAME="${CLUSTER_NAME:-laboratorio-ep02-eks}"

OPEN=false
for arg in "$@"; do
  case "$arg" in
    --open|-o) OPEN=true ;;
    -h|--help)
      echo "Uso: ./url-app.sh [--open]"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg"
      echo "Uso: ./url-app.sh [--open]"
      exit 1
      ;;
  esac
done

banner() {
  echo ""
  echo "========================================="
  echo " $1"
  echo "========================================="
  echo ""
}

banner "URL DE LA APLICACIÓN"

if ! command -v aws &> /dev/null; then
  echo "ERROR: aws CLI no está instalado."
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl no está instalado."
  exit 1
fi

# ---------------------------------------------------------------
# Recuperación de credenciales:
# 1) Valida la conexión con aws sts get-caller-identity.
# 2) Si falla, configura las credenciales con aws configure set
#    leyendo secrets.txt y vuelve a validar.
# 3) Refresca el kubeconfig del cluster EKS.
# ---------------------------------------------------------------
recover_aws() {
  echo ""
  echo "Validando conexión con AWS (aws sts get-caller-identity)..."
  if aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
    echo "OK: credenciales AWS válidas."
  else
    echo "Sin conexión válida a AWS. Configurando credenciales desde secrets.txt..."
    if [ ! -f "$SECRETS_FILE" ]; then
      echo "ERROR: no encontré secrets.txt (busqué en $SCRIPT_DIR y en el directorio actual)."
      return 1
    fi

    local akid="" sk="" tok=""
    while IFS='=' read -r key value || [ -n "$key" ]; do
      key="${key//[[:space:]]/}"
      case "$key" in
        aws_access_key_id)     akid="$value" ;;
        aws_secret_access_key) sk="$value" ;;
        aws_session_token)     tok="$value" ;;
      esac
    done < "$SECRETS_FILE"

    if [ -z "$akid" ] || [ -z "$sk" ]; then
      echo "ERROR: secrets.txt no contiene aws_access_key_id / aws_secret_access_key."
      return 1
    fi

    aws configure set aws_access_key_id     "$akid"      --region "$REGION"
    aws configure set aws_secret_access_key "$sk"
    if [ -n "$tok" ]; then
      aws configure set aws_session_token   "$tok"
    else
      aws configure set aws_session_token   "" 2>/dev/null || true
    fi
    aws configure set region                "$REGION"

    # Refrescar también las variables de entorno de esta sesión
    export AWS_ACCESS_KEY_ID="$akid"
    export AWS_SECRET_ACCESS_KEY="$sk"
    if [ -n "$tok" ]; then
      export AWS_SESSION_TOKEN="$tok"
    else
      unset AWS_SESSION_TOKEN || true
    fi

    if aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
      echo "OK: credenciales configuradas y validadas."
    else
      echo "ERROR: las credenciales de secrets.txt no son válidas (¿token de sesión expirado?)."
      echo "  Genera credenciales frescas y actualiza secrets.txt."
      return 1
    fi
  fi

  echo "Actualizando kubeconfig: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" > /dev/null 2>&1 \
    || echo "ADVERTENCIA: no pude actualizar el kubeconfig (¿existe el cluster $CLUSTER_NAME?)."
}

# Verificar acceso al cluster (con un intento de recuperación automática)
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo "No puedo acceder al namespace $NAMESPACE. Intentando recuperar credenciales..."
  recover_aws || true
  if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo ""
    echo "ERROR: no puedo acceder al namespace $NAMESPACE."
    echo "  - ¿Credenciales AWS frescas?   aws sts get-caller-identity"
    echo "  - ¿kubeconfig actualizado?     aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    exit 1
  fi
fi
echo "OK: acceso al namespace $NAMESPACE confirmado."

# Esperar a que el Service LoadBalancer tenga hostname externo
echo "Esperando el hostname del Service $SERVICE (namespace $NAMESPACE)..."
HOST=""
for i in $(seq 1 60); do
  HOST="$(kubectl get svc "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$HOST" ]; then
    break
  fi
  echo "  ... aún sin hostname ($i/60)"
  sleep 10
done

echo ""
echo "--- Service $SERVICE ---"
kubectl get svc "$SERVICE" -n "$NAMESPACE" -o wide 2>/dev/null || true
echo ""

if [ -n "$HOST" ]; then
  URL="http://$HOST"
  banner "URL: $URL"
  if [ "$OPEN" = true ]; then
    if command -v open &> /dev/null; then
      open "$URL"
    elif command -v xdg-open &> /dev/null; then
      xdg-open "$URL"
    else
      echo "(no pude abrir el navegador automáticamente)"
    fi
  fi
else
  echo "ADVERTENCIA: el Service $SERVICE no tiene hostname externo todavía."
  echo "  - ¿El frontend está desplegado?  kubectl get pods -n $NAMESPACE"
  echo "  - ¿El ELB está aprovisionando?   vuelve a intentar en 1-2 minutos."
  exit 1
fi
