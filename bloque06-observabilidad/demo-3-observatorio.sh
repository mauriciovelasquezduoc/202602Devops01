#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - DEMO 3: OBSERVATORIO DE ALARMAS (modo sala de control)
#
# ¿QUE HACE?
#   Refresca cada 15 segundos el estado de TODAS las alarmas ep02-*
#   y el histórico reciente de la métrica personalizada SaludBackend.
#   Es la vista "sala de control" para dejar corriendo mientras
#   ejecutas las demos 1 y 2 en otra terminal.
#
# CICLO DE VIDA DE UNA ALARMA (lo que verás cambiar):
#   INSUFFICIENT_DATA : la métrica aún no tiene datos
#   OK                : la condición se cumple "bien"
#   ALARM             : la condición está VIOLADA (y SNS notifica)
#
# USO:
#   bash demo-3-observatorio.sh        # Ctrl+C para salir
# ==================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${REGION:-us-east-1}"
NAMESPACE="Ep02/Microservicio"

AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; NC='\033[0m'

SECRETS_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/secrets.txt"
[ -f "$SECRETS_FILE" ] && { R="$(grep -E '^AWS_REGION=' "$SECRETS_FILE" || true)"; [ -n "$R" ] && REGION="${R#AWS_REGION=}"; }

clear
echo -e "${AZUL}============================================================${NC}"
echo -e "${AZUL}  OBSERVATORIO ep02 — Ctrl+C para salir${NC}"
echo -e "${AZUL}============================================================${NC}"

while true; do
  echo -e "\n${AZUL}[$(date '+%H:%M:%S')] Estado de alarmas ep02-*${NC}"
  aws cloudwatch describe-alarms --region "$REGION" \
    --query 'MetricAlarms[?starts_with(AlarmName, `ep02`)].[AlarmName,StateValue,StateUpdatedTimestamp]' \
    --output table 2>/dev/null || echo "  (no se pudo consultar CloudWatch)"

  echo -e "\n${AZUL}Histórico de SaludBackend (últimos 15 min, promedio por minuto)${NC}"
  INICIO=$(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)
  aws cloudwatch get-metric-statistics --region "$REGION" \
    --namespace "$NAMESPACE" --metric-name SaludBackend \
    --start-time "$INICIO" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 60 --statistic Minimum \
    --query 'sort_by(Datapoints, &Timestamp)[].[Timestamp,Minimum]' \
    --output table 2>/dev/null || echo "  (sin datos aún: ejecuta push-metrica.sh o una demo)"

  echo -e "${AMAR}Leyenda: 1.0 = salud OK | 0.0 = el microservicio dejó de responder${NC}"
  echo -e "${AMAR}Si una alarma está en ALARM y configuraste email en SNS, ya llegó el aviso.${NC}"
  sleep 15
done
