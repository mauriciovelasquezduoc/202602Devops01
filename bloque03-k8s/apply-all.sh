#!/bin/bash

set -e

aws eks update-kubeconfig   --region us-east-1   --name laboratorio-ep03-eks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "=== Kubernetes Config Generator ==="

# Verificar que exista values.yaml
if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: No se encontro values.yaml"
    exit 1
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