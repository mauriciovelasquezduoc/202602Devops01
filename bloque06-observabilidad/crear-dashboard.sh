#!/bin/bash
set -euo pipefail

# =====================================================
# Script: crear-dashboard.sh
# Crea un Dashboard personalizado en CloudWatch para el
# laboratorio ep02: métricas del microservicio, estado de
# las alarmas, CPU del nodo y errores del LoadBalancer.
#
# Uso (dentro del contenedor, después de ejecutar.sh):
#   bash crear-dashboard.sh
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/../secrets.txt"
DASH_NAME="ep02-observabilidad"

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
fi

REGION="${AWS_REGION:-us-east-1}"

titulo() { echo ""; echo "=== $1 ==="; }

echo "Validando credenciales AWS..."
if ! aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
  echo "ERROR: credenciales AWS no válidas o expiradas."
  exit 1
fi
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# ---------- Datos que necesita el dashboard ----------

# 1. ARNs REALES de las alarmas ep02 creadas por ejecutar.sh
#    (la de CPU lleva sufijo: ep02-cpu-nodo-alta-<ultimos6>)
ALARM_ARNS="$(aws cloudwatch describe-alarms --region "$REGION" \
  --query 'MetricAlarms[?starts_with(AlarmName, `ep02`)].AlarmArn' \
  --output text 2>/dev/null | tr '\t' '\n' | paste -sd, - || true)"

# 2. Nombre del Classic LoadBalancer (dimensión de AWS/ELB)
LB_HOSTNAME="$(kubectl get svc ep02-frontend -n ep02 \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
ELB_NAME=""
if [ -n "$LB_HOSTNAME" ]; then
  # DNS del CLB: <nombre>-<12digitos>.<region>.elb.amazonaws.com
  ELB_NAME="${LB_HOSTNAME%%-*}"
fi

# 3. IDs de instancias EC2 (providerID: aws:///<region>/<zone>/i-xxx)
INSTANCE_IDS="$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}' 2>/dev/null \
  | grep -oE 'i-[a-z0-9]+' | paste -sd, - || true)"

titulo "Datos detectados"
echo "  Region:       $REGION"
echo "  ELB:          ${ELB_NAME:-no detectado (widget ELB se omite)}"
echo "  Instancias:   ${INSTANCE_IDS:-no detectadas (widget EC2 se omite)}"
echo "  Alarmas:      $(echo "$ALARM_ARNS" | tr ',' '\n' | grep -c . || true) detectadas"

# ---------- Construir el cuerpo del dashboard ----------
DASH_FILE="$(mktemp)"
cat > "$DASH_FILE" <<EOF
{
  "widgets": [
    {
      "type": "text", "x": 0, "y": 0, "width": 24, "height": 3,
      "properties": {
        "markdown": "# Sala de control ep02\\nMicroservicio: **SaludBackend** (métrica personalizada) · estado de alarmas · CPU del nodo · errores del ELB.\\n\\nComando para publicar la métrica: **bash push-metrica.sh** · las demos 1 y 2 disparan las alarmas."
      }
    },
    {
      "type": "metric", "x": 0, "y": 3, "width": 12, "height": 6,
      "properties": {
        "title": "SaludBackend (0 = caído, 1 = OK)",
        "region": "${REGION}",
        "view": "timeSeries",
        "stat": "Maximum",
        "period": 60,
        "yAxis": { "min": 0, "max": 1 },
        "metrics": [
          [ "Ep02/Microservicio", "SaludBackend" ]
        ]
      }
    },
    {
      "type": "metric", "x": 12, "y": 3, "width": 12, "height": 6,
      "properties": {
        "title": "PodsActivos backend (Ready)",
        "region": "${REGION}",
        "view": "timeSeries",
        "stat": "Maximum",
        "period": 60,
        "metrics": [
          [ "Ep02/Microservicio", "PodsActivos" ]
        ]
      }
    },
    {
      "type": "metric", "x": 0, "y": 9, "width": 12, "height": 6,
      "properties": {
        "title": "CPU del nodo (EC2 %)",
        "region": "${REGION}",
        "view": "timeSeries",
        "stat": "Average",
        "period": 60,
        "yAxis": { "min": 0 },
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", "InstanceId", "${INSTANCE_IDS:-i-unknown}" ]
        ]
      }
    },
    {
      "type": "metric", "x": 12, "y": 9, "width": 12, "height": 6,
      "properties": {
        "title": "LoadBalancer: requests y errores 5XX",
        "region": "${REGION}",
        "view": "timeSeries",
        "stat": "Sum",
        "period": 60,
        "metrics": [
          [ "AWS/ELB", "RequestCount", "LoadBalancerName", "${ELB_NAME:-none}", { "stat": "Sum" } ],
          [ ".", "HTTPCode_ELB_5XX", ".", ".", { "stat": "Sum" } ],
          [ ".", "UnHealthyHostCount", ".", ".", { "stat": "Maximum" } ]
        ]
      }
    },
    {
      "type": "metric", "x": 0, "y": 15, "width": 12, "height": 6,
      "properties": {
        "title": "LoadBalancer: hosts saludables",
        "region": "${REGION}",
        "view": "timeSeries",
        "stat": "Maximum",
        "period": 60,
        "metrics": [
          [ "AWS/ELB", "HealthyHostCount", "LoadBalancerName", "${ELB_NAME:-none}" ]
        ]
      }
    }
  ]
}
EOF

# 4. Widget de alarmas: se agrega SOLO si hay alarmas reales detectadas
if [ -n "${ALARM_ARNS:-}" ] && [ "$ALARM_ARNS" != "," ]; then
  # Armamos el widget con python para no romper el JSON
  python3 - "$DASH_FILE" "$ALARM_ARNS" "$REGION" <<'PYEOF'
import json, sys
path, arns, region = sys.argv[1], sys.argv[2], sys.argv[3]
alarm_list = [a.strip() for a in arns.split(",") if a.strip()]
widget = {
    "type": "alarm", "x": 12, "y": 15, "width": 12, "height": 6,
    "properties": {
        "title": "Estado de las alarmas",
        "region": region,
        "alarms": [{"arn": a} for a in alarm_list],
    },
}
dash = json.load(open(path))
dash["widgets"].append(widget)
json.dump(dash, open(path, "w"))
PYEOF
  echo "  Widget de alarmas: agregado con $(echo "$ALARM_ARNS" | tr ',' '\n' | grep -c .) alarmas"
fi

titulo "Creando dashboard $DASH_NAME"
if aws cloudwatch put-dashboard \
    --region "$REGION" \
    --dashboard-name "$DASH_NAME" \
    --dashboard-body "file://$DASH_FILE"; then
  rm -f "$DASH_FILE"
  URL="https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${DASH_NAME};start=PT3H"
  echo ""
  echo "OK: dashboard creado."
  echo "Ábrelo en el navegador (desde tu Mac, no desde el contenedor):"
  echo "  $URL"
  echo ""
  echo "También en la consola: CloudWatch → Dashboards → $DASH_NAME"
else
  STATUS=$?
  rm -f "$DASH_FILE"
  echo "ERROR: no se pudo crear el dashboard (exit $STATUS)."
  echo "Si el error es de permisos, es limitación de la sesión Academy:"
  echo "  las alarmas y métricas siguen visibles en la consola."
  exit $STATUS
fi
