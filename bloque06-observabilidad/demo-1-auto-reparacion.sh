#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - DEMO 1: AUTO-REPARACIÓN (borrar pods y ver cómo se
#                            reconstruyen solos)
#
# ¿QUE DEMUESTRA?
#   Kubernetes funciona por "estado deseado" (Declarative):
#   el ReplicaSet promete mantener N réplicas. Si borras un pod,
#   el controlador NOTA la diferencia y crea otro. Nadie lo
#   llama a mano: es un bucle de reconciliación.
#
#   Además, publicamos lo observado en CloudWatch (métrica
#   personalizada) para que la alarma ep02-backend-salud y
#   ep02-backend-pods salten EN VIVO.
#
# USO:
#   bash demo-1-auto-reparacion.sh
# ==================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${REGION:-us-east-1}"
NAMESPACE="ep02"
CW_NAMESPACE="Ep02/Microservicio"

AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${AZUL}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()    { echo -e "${VERDE}  ✔ $*${NC}"; }
warn()  { echo -e "${AMAR}  ⚠ $*${NC}"; }
paso()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
concepto() { echo -e "${AMAR}🔎 CONCEPTO: $*${NC}"; }

# Región desde secrets.txt si existe
SECRETS_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/secrets.txt"
[ -f "$SECRETS_FILE" ] && { R="$(grep -E '^AWS_REGION=' "$SECRETS_FILE" || true)"; [ -n "$R" ] && REGION="${R#AWS_REGION=}"; }

# ------------------------------------------------------------------
paso "ESCENA 0 — Verificar que todo está sano ANTES del desastre"
# ------------------------------------------------------------------
kubectl get pods -n "$NAMESPACE" -o wide || { echo "No hay cluster/app. Aplica bloque03 primero."; exit 1; }
bash "$SCRIPT_DIR/push-metrica.sh"

echo ""
concepto "ReplicaSet = promesa de N réplicas. Borrar un pod NO es un error: es un \
evento que Kubernetes atiende solo. En producción esto pasa igual cuando un nodo muere."

echo ""
read -r -p "▶ Presiona ENTER para provocar el desastre (borrar 1 pod del backend y 1 del frontend)..."

# ------------------------------------------------------------------
paso "ESCENA 1 — Borrar pods (simular falla)"
# ------------------------------------------------------------------
BACKEND_POD="$(kubectl get pods -n "$NAMESPACE" -l app=ep02-backend -o jsonpath='{.items[0].metadata.name}')"
FRONTEND_POD="$(kubectl get pods -n "$NAMESPACE" -l app=ep02-frontend -o jsonpath='{.items[0].metadata.name}')"
T0=$(date +%s)

log "Eliminando pod del backend:   $BACKEND_POD"
kubectl delete pod "$BACKEND_POD" -n "$NAMESPACE"
log "Eliminando pod del frontend:  $FRONTEND_POD"
kubectl delete pod "$FRONTEND_POD" -n "$NAMESPACE"
ok "Desastre provocado en T+0s. Mira cómo el sistema reacciona solo..."

# ------------------------------------------------------------------
paso "ESCENA 2 — Observar la reconstrucción (timeline en vivo)"
# ------------------------------------------------------------------
concepto "Fases que verás: Terminating -> (ReplicaSet detecta el faltante) -> ContainerCreating \
-> Ready. El backend tarda más: su readinessProbe espera 50s antes de dar por listo el pod."

LINEA_REPORT="$SCRIPT_DIR/reports/demo1-timeline-$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$SCRIPT_DIR/reports"
{ echo "# Demo 1 — Auto-reparación ($(date '+%Y-%m-%d %H:%M:%S'))"; echo; echo "| T+ | Backend | Frontend | Salud |"; echo "|---|---|---|---|"; } > "$LINEA_REPORT"

BACKEND_READY=false
FRONTEND_READY=false
while true; do
  T_NOW=$(( $(date +%s) - T0 ))
  BE_LINE="$(kubectl get pods -n "$NAMESPACE" -l app=ep02-backend  --no-headers 2>/dev/null | awk '{print $1" "$2" "$3}' | tr '\n' ';')"
  FE_LINE="$(kubectl get pods -n "$NAMESPACE" -l app=ep02-frontend --no-headers 2>/dev/null | awk '{print $1" "$2" "$3}' | tr '\n' ';')"
  # Contar solo pods REALMENTE listos: descarta los que están Terminating
  # (un pod eliminado sigue mostrando "1/1" mientras muere — contador trampa).
  BE_READY_N="$(kubectl get pods -n "$NAMESPACE" -l app=ep02-backend -o json 2>/dev/null | jq '[.items[] | select(.metadata.deletionTimestamp == null) | select(.status.phase == "Running") | select([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length > 0)] | length' 2>/dev/null)"
  FE_READY_N="$(kubectl get pods -n "$NAMESPACE" -l app=ep02-frontend -o json 2>/dev/null | jq '[.items[] | select(.metadata.deletionTimestamp == null) | select(.status.phase == "Running") | select([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length > 0)] | length' 2>/dev/null)"

  # Salud real del backend (0 mientras no haya pod o no responda)
  if [ "${BE_READY_N:-0}" -ge 1 ] && kubectl exec -n "$NAMESPACE" deploy/ep02-backend -- \
       curl -sf -m 5 http://localhost:8080/actuator/health >/dev/null 2>&1; then SALUD=1; else SALUD=0; fi
  PODS_N="$BE_READY_N"
  aws cloudwatch put-metric-data --region "$REGION" --namespace "$CW_NAMESPACE" \
      --metric-name SaludBackend --dimensions Deployment=ep02-backend --value "$SALUD" >/dev/null 2>&1 || true
  aws cloudwatch put-metric-data --region "$REGION" --namespace "$CW_NAMESPACE" \
      --metric-name PodsActivos --dimensions Deployment=ep02-backend --value "$PODS_N" >/dev/null 2>&1 || true

  echo -e "${AZUL}T+${T_NOW}s${NC}  backend: ${BE_LINE:-<sin pods>}   frontend: ${FE_LINE:-<sin pods>}   salud=$SALUD"
  echo "| ${T_NOW}s | ${BE_LINE} | ${FE_LINE} | $SALUD |" >> "$LINEA_REPORT"

  # El backend está "recuperado" solo cuando: el pod original ya no existe
  # (no es un Terminating residual) + hay un pod Ready + health responde.
  if [ "${BE_READY_N:-0}" -ge 1 ] && ! kubectl get pod "$BACKEND_POD" -n "$NAMESPACE" >/dev/null 2>&1 \
       && [ "$SALUD" -eq 1 ] && [ "$BACKEND_READY" = false ]; then
    BACKEND_READY=true; ok "BACKEND recuperado (pod original eliminado, nuevo Ready y health UP) en T+${T_NOW}s"
  fi
  [ "${FE_READY_N:-0}" -ge 2 ] && [ "$FRONTEND_READY" = false ] && {
    FRONTEND_READY=true; ok "FRONTEND recuperado (2/2 Ready) en T+${T_NOW}s"; }

  # Terminamos cuando backend esté listo (es el más lento) o pasados 5 min
  [ "$BACKEND_READY" = true ] && break
  [ "$T_NOW" -ge 300 ] && { warn "Timeout de 5 minutos; revisa kubectl describe pod. Continuando..."; break; }
  sleep 5
done

T_REC=$(( $(date +%s) - T0 ))
[ "$FRONTEND_READY" = false ] && { # esperar un poco más al frontend si faltó
  for _ in $(seq 1 12); do
    N=$(kubectl get pods -n "$NAMESPACE" -l app=ep02-frontend --no-headers 2>/dev/null | grep -c ' 1/1' || true)
    [ "${N:-0}" -ge 2 ] && { ok "FRONTEND recuperado (2/2 Ready) en T+$(( $(date +%s) - T0 ))s"; FRONTEND_READY=true; break; }
    sleep 5
  done
}

# ------------------------------------------------------------------
paso "ESCENA 3 — La evidencia: eventos y alarmas"
# ------------------------------------------------------------------
echo "Eventos recientes del namespace (los últimos del desastre):"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -8 || true

echo ""
concepto "Nadie ejecutó kubectl apply ni creó pods a mano. El ReplicaSet NOTÓ que faltaba \
una réplica y la recolocó. Esto es auto-reparación (self-healing)."

echo ""
log "¿Saltaron las alarmas? (dan ALARM 60-120s después del desastre)"
aws cloudwatch describe-alarms --region "$REGION" \
  --alarm-names ep02-backend-salud ep02-backend-pods \
  --query 'MetricAlarms[].[AlarmName,StateValue,StateReason]' --output table 2>/dev/null || \
  warn "No se pudo consultar CloudWatch."

cat > "$SCRIPT_DIR/reports/demo1-resumen-$(date +%Y%m%d-%H%M%S).md" <<EOF
# Demo 1 — Resumen auto-reparación
Pods eliminados: $BACKEND_POD (backend), $FRONTEND_POD (frontend)
Backend recuperado (health UP): ${BACKEND_READY} — T+${T_REC}s
Frontend recuperado (2/2):      ${FRONTEND_READY}
Timeline completo: $(basename "$LINEA_REPORT")
EOF

echo ""
echo -e "${VERDE}DEMO 1 COMPLETADA — recuperación en T+${T_REC}s${NC}"
echo -e "📝 Para tu informe: registra el tiempo de recuperación y explica por qué el backend"
echo -e "   tarda más que el frontend (readinessProbe con initialDelaySeconds: 50)."
echo -e "   El timeline quedó en reports/demo1-timeline-*.md"
