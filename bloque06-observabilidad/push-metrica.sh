#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - OBSERVABILIDAD / Métrica personalizada en CloudWatch
#
# ¿QUE HACE?
#   Lee el estado REAL del microservicio backend (pods activos y salud)
#   y lo PUBLICA en CloudWatch como métrica personalizada.
#
# ¿CONCEPTO?
#   CloudWatch recibe métricas de dos formas:
#     1) Automáticas: EC2, ELB, EKS ya publican las suyas (no haces nada).
#     2) Push manual: TU aplicación o script publica la suya con
#        `aws cloudwatch put-metric-data`  <-- este script.
#
#   Aquí publicamos el namespace personalizado  Ep02/Microservicio  con:
#     - PodsActivos   : cuántos pods Ready tiene el backend
#     - SaludBackend  : 1 si /actuator/health responde, 0 si no
#
# USO:
#   bash push-metrica.sh            # publica una vez y muestra el resultado
#   watch -n 15 bash push-metrica.sh   # (opcional) modo monitor
# ==================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${REGION:-us-east-1}"
SECRETS_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/secrets.txt"
NAMESPACE="ep02"
APP="ep02-backend"
CW_NAMESPACE="Ep02/Microservicio"

# Colores (misma paleta que el resto del laboratorio)
AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${AZUL}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${VERDE}  ✔ $*${NC}"; }
warn() { echo -e "${AMAR}  ⚠ $*${NC}"; }
err()  { echo -e "${ROJO}  ✘ $*${NC}"; }

# Cargar región desde secrets.txt si existe (mismo patrón que bloque01)
if [ -f "$SECRETS_FILE" ]; then
  REGION_LINE="$(grep -E '^AWS_REGION=' "$SECRETS_FILE" || true)"
  [ -n "$REGION_LINE" ] && REGION="${REGION_LINE#AWS_REGION=}"
fi

# ------------------------------------------------------------------
# 1. PODS ACTIVOS: pods en fase Running Y con condición Ready=True
# ------------------------------------------------------------------
PODS_ACTIVOS=$(kubectl get pods -n "$NAMESPACE" -l "app=$APP" \
  -o json 2>/dev/null | jq '[.items[]
      | select(.status.phase == "Running")
      | select([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length > 0)
    ] | length' 2>/dev/null)
[ -z "$PODS_ACTIVOS" ] && PODS_ACTIVOS=0

# ------------------------------------------------------------------
# 2. SALUD: golpeamos /actuator/health DENTRO del pod (Actuator)
# ------------------------------------------------------------------
if kubectl exec -n "$NAMESPACE" "deploy/$APP" -- \
     curl -sf -m 5 http://localhost:8080/actuator/health >/dev/null 2>&1; then
  SALUD=1
else
  SALUD=0
fi

log "Estado medido del microservicio $APP:"
[ "$PODS_ACTIVOS" -gt 0 ] && ok  "PodsActivos  = $PODS_ACTIVOS" || err "PodsActivos  = $PODS_ACTIVOS"
[ "$SALUD" -eq 1 ]       && ok  "SaludBackend = $SALUD (UP)"   || err "SaludBackend = $SALUD (DOWN)"

# ------------------------------------------------------------------
# 3. PUBLICAR en CloudWatch (push de métrica personalizada)
# ------------------------------------------------------------------
log "Publicando en CloudWatch namespace '$CW_NAMESPACE'..."

if aws cloudwatch put-metric-data --region "$REGION" \
     --namespace "$CW_NAMESPACE" \
     --metric-name PodsActivos \
     --dimensions Deployment="$APP" \
     --value "$PODS_ACTIVOS" 2>/dev/null; then
  ok "put-metric-data PodsActivos=$PODS_ACTIVOS publicado"
else
  warn "No se pudo publicar PodsActivos (revisa permisos cloudwatch:PutMetricData en Academy)."
fi

if aws cloudwatch put-metric-data --region "$REGION" \
     --namespace "$CW_NAMESPACE" \
     --metric-name SaludBackend \
     --dimensions Deployment="$APP" \
     --value "$SALUD" 2>/dev/null; then
  ok "put-metric-data SaludBackend=$SALUD publicado"
else
  warn "No se pudo publicar SaludBackend (revisa permisos cloudwatch:PutMetricData en Academy)."
fi

echo ""
log "🔎 Para verlas: Consola AWS → CloudWatch → Metrics → All metrics → Custom namespaces → Ep02/Microservicio"
