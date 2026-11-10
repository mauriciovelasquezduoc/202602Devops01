#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - DEMO 2: PRUEBA DE CARGA (ver al HPA escalar y a las
#                        alarmas entrar en acción)
#
# ¿QUE DEMUESTRA?
#   1. El HPA escala REPLICAAS (horizontal) cuando la CPU promedio
#      de los pods supera el objetivo (backend 70%, frontend 60%).
#   2. El nodo t3.large es un recurso COMPARTIDO: si la carga sube
#      demasiado, la alarma ep02-cpu-nodo-alta puede saltar.
#   3. Si el backend se satura, el balanceador reporta 5XX y salta
#      la alarma ep02-elb-5xx.
#   4. Al bajar la carga, el HPA espera un "periodo de
#      estabilización" (~5 min) antes de devolver réplicas.
#      Escalar rápido, bajar despacio: eso es sana operación.
#
# USO:
#   bash demo-2-prueba-carga.sh                    # 5 min de carga, 8 workers
#   DURACION=180 WORKERS=6 bash demo-2-prueba-carga.sh
#   ESPERAR_BAJADA=1 bash demo-2-prueba-carga.sh   # quedarse mirando el downsizing
# ==================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${REGION:-us-east-1}"
NAMESPACE="ep02"
DURACION="${DURACION:-300}"     # segundos de carga
WORKERS="${WORKERS:-8}"         # procesos curl simultáneos
# El nginx del frontend hace proxy de /ep02/* al backend:8080 (ver nginx.conf)
LOAD_PATH="${LOAD_PATH:-/ep02/actuator/health}"

AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${AZUL}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()      { echo -e "${VERDE}  ✔ $*${NC}"; }
warn()    { echo -e "${AMAR}  ⚠ $*${NC}"; }
paso()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
concepto(){ echo -e "${AMAR}🔎 CONCEPTO: $*${NC}"; }

SECRETS_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/secrets.txt"
[ -f "$SECRETS_FILE" ] && { R="$(grep -E '^AWS_REGION=' "$SECRETS_FILE" || true)"; [ -n "$R" ] && REGION="${R#AWS_REGION=}"; }

# ------------------------------------------------------------------
paso "PASO 1 — Ubicar la URL pública del frontend"
# ------------------------------------------------------------------
LB_DNS="$(kubectl get svc ep02-frontend -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
[ -n "$LB_DNS" ] || { echo "No hay LoadBalancer en svc/ep02-frontend. Aplica el bloque03."; exit 1; }
URL="http://$LB_DNS$LOAD_PATH"
ok "URL de carga: $URL"

log "Verificando conectividad..."
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$URL" || echo "000")
[ "$CODE" = "200" ] || warn "La URL respondió $CODE (se esperaba 200). Si es 000/502, espera a que el backend esté Ready."

# ------------------------------------------------------------------
paso "PASO 2 — Línea base (antes de la carga)"
# ------------------------------------------------------------------
concepto "TARGETS = %CPU promedio de los pods vs objetivo del HPA. REPLICAS es lo que el \
HPA decide. La métrica la entrega el Metrics Server (bloque01)."
kubectl get hpa -n "$NAMESPACE"
kubectl top pods -n "$NAMESPACE" 2>/dev/null | head -8 || warn "Metrics Server aún calentando; reintenta en 1 min."
kubectl top nodes 2>/dev/null || true
bash "$SCRIPT_DIR/push-metrica.sh"

echo ""
echo -e "${AMAR}  Se generarán $WORKERS procesos de peticiones HTTP durante $DURACION segundos.${NC}"
echo -e "${AMAR}  En otra terminal puedes acompañar con:  kubectl get hpa -n $NAMESPACE -w${NC}"
read -r -p "▶ Presiona ENTER para COMENZAR LA CARGA..."

# ------------------------------------------------------------------
paso "PASO 3 — Generando carga (en vivo)"
# ------------------------------------------------------------------
REPORT="$SCRIPT_DIR/reports/demo2-carga-$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$SCRIPT_DIR/reports"
HITS_DIR="$(mktemp -d)"
END=$(( $(date +%s) + DURACION ))

# Workers: cada uno repite curl sin pausa hasta que se acabe el tiempo.
worker() {
  local id="$1" dest="$HITS_DIR/worker-$id.log"
  while [ "$(date +%s)" -lt "$END" ]; do
    curl -s -o /dev/null -m 10 -w '%{http_code}\n' "$URL" >> "$dest" 2>/dev/null || echo "ERR" >> "$dest"
  done
}
for i in $(seq 1 "$WORKERS"); do worker "$i" & done

# Monitor: imprime y registra la evolución cada 15s.
monitorear() {
  echo "| T+ | HPA backend (TARGETS/REPLICAS) | HPA frontend | CPU pods backend |" >> "$REPORT"
  echo "|---|---|---|---|" >> "$REPORT"
  while [ "$(date +%s)" -lt "$END" ]; do
    T=$(( END - $(date +%s) ))
    HPA_BE="$(kubectl get hpa ep02-backend-hpa  -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $3" | répl: "$6}' || echo '-')"
    HPA_FE="$(kubectl get hpa ep02-frontend-hpa -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $3" | répl: "$6}' || echo '-')"
    TOP_BE="$(kubectl top pods -n "$NAMESPACE" -l app=ep02-backend 2>/dev/null | tail -n +2 | awk '{print $1":"$2}' | tr '\n' ' ' || echo '-')"
    echo -e "${AZUL}T-${T}s restantes${NC}  backend-hpa[${HPA_BE}]  frontend-hpa[répl: ${HPA_FE}]  cpu-pods: ${TOP_BE:-calentando...}"
    echo "| $((DURACION - T)) | $HPA_BE | $HPA_FE | $TOP_BE |" >> "$REPORT"
    sleep 15
  done
}
monitorear &  MON_PID=$!

# Esperar el fin de la ventana de carga
while [ "$(date +%s)" -lt "$END" ]; do sleep 5; done
wait "$MON_PID" 2>/dev/null || true
wait

# ------------------------------------------------------------------
paso "PASO 4 — Resultados de la carga"
# ------------------------------------------------------------------
TOTAL=$(cat "$HITS_DIR"/worker-*.log 2>/dev/null | wc -l | tr -d ' ')
OK_200=$(cat "$HITS_DIR"/worker-*.log 2>/dev/null | grep -c '^200' || true)
ERRORES=$(cat "$HITS_DIR"/worker-*.log 2>/dev/null | grep -vc '^200' || true)
ok "Peticiones totales: ${TOTAL:-0}  |  200 OK: ${OK_200:-0}  |  errores/timeouts: ${ERRORES:-0}"
rm -rf "$HITS_DIR"

echo ""
log "Estado del HPA al terminar la carga:"
kubectl get hpa -n "$NAMESPACE"
log "CPU de los pods (¿cuántas réplicas nuevas?)"
kubectl top pods -n "$NAMESPACE" 2>/dev/null | head -10 || true
log "CPU del nodo (¿saltó ep02-cpu-nodo-alta?)"
kubectl top nodes 2>/dev/null || true

concepto "Mira el histórico: kubectl get hpa -n $NAMESPACE -w. Al bajar la carga, el HPA \
NO baja réplicas de inmediato: espera un periodo de estabilización (~5 min) para no \
oscilar (flapping). Escalar rápido, reducir despacio."

cat >> "$REPORT" <<EOF

## Resumen
- URL: $URL
- Duración: ${DURACION}s | Workers: $WORKERS
- Peticiones: $TOTAL | 200: $OK_200 | errores: $ERRORES
- HPA final: $(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1": "$3" -> "$6" réplicas"}' | tr '\n' ' ')
EOF
ok "Evidencia guardada en $REPORT"

# ------------------------------------------------------------------
if [ "${ESPERAR_BAJADA:-0}" = "1" ]; then
  paso "PASO 5 — Observar el ESCALADO HACIA ABAJO (hasta 15 min)"
  echo -e "Mantén esta ventana abierta. Cuando TARGETS baje del objetivo y pasen ~5 min, REPLICAS retrocede."
  for _ in $(seq 1 60); do
    kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null
    BE=$(kubectl get hpa ep02-backend-hpa -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $6}')
    FE=$(kubectl get hpa ep02-frontend-hpa -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $6}')
    [ "${BE:-99}" = "1" ] && [ "${FE:-99}" = "2" ] && { ok "El sistema volvió al mínimo. Cooldown completado."; break; }
    sleep 15
  done
fi

# ------------------------------------------------------------------
paso "PASO 5 — ¿Saltaron las alarmas?"
# ------------------------------------------------------------------
aws cloudwatch describe-alarms --region "$REGION" \
  --query 'MetricAlarms[?starts_with(AlarmName, `ep02`)].[AlarmName,StateValue,MetricName]' \
  --output table 2>/dev/null || warn "No se pudo consultar CloudWatch."
echo ""
echo -e "📝 Para tu informe: compara la línea base vs el pico (réplicas, CPU por pod, CPU del nodo)."
echo -e "   Explica con tus palabras la diferencia entre escalar PODS (HPA) y saturar el NODO."
