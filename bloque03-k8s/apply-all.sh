#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SECRETS_FILE="${SCRIPT_DIR}/../secrets.txt"

echo "=== Kubernetes Config Generator ==="

# Cargar credenciales y AWSAccountId desde secrets.txt
ACCOUNT_ID=""
if [ -f "$SECRETS_FILE" ]; then
    echo "Leyendo $SECRETS_FILE..."
    while IFS='=' read -r key value || [ -n "$key" ]; do
        key="${key//[[:space:]]/}"
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [ -z "$value" ] && continue
        export "$key=$value"
    done < "$SECRETS_FILE"

    # Compatibilidad con claves AWS en minusculas.
    [ -n "${aws_access_key_id:-}" ] && export AWS_ACCESS_KEY_ID="$aws_access_key_id"
    [ -n "${aws_secret_access_key:-}" ] && export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
    [ -n "${aws_session_token:-}" ] && export AWS_SESSION_TOKEN="$aws_session_token"
    [ -n "${AWS_REGION:-}" ] && export AWS_DEFAULT_REGION="$AWS_REGION"

    ACCOUNT_ID="${AWSAccountId:-}"
else
    echo "ADVERTENCIA: No se encontro $SECRETS_FILE"
fi

aws eks update-kubeconfig --region "${AWS_REGION:-us-east-1}" --name laboratorio-ep02-eks

# Verificar que exista values.yaml
if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: No se encontro values.yaml"
    exit 1
fi

# Reemplazar el placeholder <AWSAccountId> de values.yaml por la cuenta real de secrets.txt
if [ -n "$ACCOUNT_ID" ]; then
    if grep -q '<AWSAccountId>' "$VALUES_FILE"; then
        echo "Reemplazando <AWSAccountId> por ${ACCOUNT_ID} en values.yaml..."
        sed "s|<AWSAccountId>|${ACCOUNT_ID}|g" "$VALUES_FILE" > "$VALUES_FILE.tmp"
        mv "$VALUES_FILE.tmp" "$VALUES_FILE"
    else
        echo "values.yaml no contiene <AWSAccountId>, se deja sin cambios"
    fi
else
    echo "ADVERTENCIA: AWSAccountId no definido en $SECRETS_FILE, values.yaml queda sin cambios"
fi

# Crear directorio de salida
mkdir -p "$OUTPUT_DIR"

# Cargar variables desde values.yaml
echo "1/3 Leyendo valores desde values.yaml..."

# Exportar todas las variables
set -a
source "$VALUES_FILE"
set +a

echo "   Variables cargadas"

# Generar YAMLs desde templates
echo ""
echo "2/3 Generando manifiestos..."
for template in "$TEMPLATES_DIR"/*.yaml; do
    filename=$(basename "$template")
    cp "$template" "$OUTPUT_DIR/$filename"
    
    # Reemplazar cada variable ${KEY} usando awk
    awk '{
        line = $0
        while (match(line, /\$\{[A-Z_0-9]+\}/)) {
            var = substr(line, RSTART + 2, RLENGTH - 3)
            value = ENVIRON[var]
            if (value != "") {
                line = substr(line, 1, RSTART - 1) value substr(line, RSTART + RLENGTH)
            } else {
                break
            }
        }
        print line
    }' "$OUTPUT_DIR/$filename" > "$OUTPUT_DIR/$filename.tmp"
    mv "$OUTPUT_DIR/$filename.tmp" "$OUTPUT_DIR/$filename"
    
    echo "   - $filename"
done

# Aplicar manifiestos
echo ""
echo "3/3 Aplicando manifiestos a Kubernetes..."
kubectl apply -f "$OUTPUT_DIR/namespace.yaml"
kubectl apply -f "$OUTPUT_DIR/database-secret.yaml"
kubectl apply -f "$OUTPUT_DIR/database-deployment.yaml"
kubectl apply -f "$OUTPUT_DIR/database-service.yaml"
kubectl apply -f "$OUTPUT_DIR/backend-deployment.yaml"
kubectl apply -f "$OUTPUT_DIR/backend-service.yaml"
kubectl apply -f "$OUTPUT_DIR/frontend-deployment.yaml"
kubectl apply -f "$OUTPUT_DIR/frontend-service.yaml"
kubectl apply -f "$OUTPUT_DIR/backend-hpa.yaml"
kubectl apply -f "$OUTPUT_DIR/frontend-hpa.yaml"

echo ""
echo "=== Despliegue completado ==="
kubectl get all -n "$NAMESPACE"