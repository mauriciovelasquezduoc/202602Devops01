#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - LIMPIEZA de la observabilidad
#
# Elimina SOLO lo creado por este bloque (alarmas + topic SNS).
# NO toca el cluster, la app ni los pods.
#   - Alarmas ep02-*          (CloudWatch, gratis pero ordenado)
#   - Topic SNS ep02-alertas  (+ suscripciones de email)
#   - Métrica personalizada Ep02/Microservicio
#     (los datos expiran solos en ~2 semanas; CloudWatch no permite
#      borrar métricas, así que simplemente deja de publicarse)
#
# Para eliminar TODO el laboratorio: usa ../aws-limpiar.sh o ../borrarTodo.sh
# ==================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${REGION:-us-east-1}"
SNS_TOPIC="ep02-alertas"

AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; NC='\033[0m'
log() { echo -e "${AZUL}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()  { echo -e "${VERDE}  ✔ $*${NC}"; }
warn(){ echo -e "${AMAR}  ⚠ $*${NC}"; }

SECRETS_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/secrets.txt"
[ -f "$SECRETS_FILE" ] && { R="$(grep -E '^AWS_REGION=' "$SECRETS_FILE" || true)"; [ -n "$R" ] && REGION="${R#AWS_REGION=}"; }

echo -e "${AMAR}Se eliminarán las alarmas ep02-* y el topic SNS '$SNS_TOPIC'.${NC}"
read -r -p "▶ ¿Continuar? (s/N): " CONF
[ "${CONF:-}" = "s" ] || { echo "Cancelado."; exit 0; }

log "Borrando alarmas ep02-*..."
NOMBRES="$(aws cloudwatch describe-alarms --region "$REGION" \
  --query 'MetricAlarms[?starts_with(AlarmName, `ep02`)].AlarmName' --output text 2>/dev/null || true)"
if [ -n "$NOMBRES" ]; then
  # shellcheck disable=SC2086
  aws cloudwatch delete-alarms --region "$REGION" --alarm-names $NOMBRES >/dev/null 2>&1 \
    && ok "Alarmas borradas: $NOMBRES" || warn "No se pudieron borrar todas las alarmas."
else
  ok "No había alarmas ep02-*."
fi

log "Borrando topic SNS $SNS_TOPIC..."
ARN="$(aws sns list-topics --region "$REGION" --query "Topics[?ends_with(TopicArn, ':$SNS_TOPIC')].TopicArn" --output text 2>/dev/null || true)"
if [ -n "$ARN" ]; then
  aws sns delete-topic --region "$REGION" --topic-arn "$ARN" >/dev/null 2>&1 \
    && ok "Topic SNS borrado: $ARN" || warn "No se pudo borrar el topic."
else
  ok "No existía el topic SNS."
fi

log "La métrica Ep02/Microservicio dejará de recibir datos y expirará sola."
ok "Limpieza del bloque 06 terminada."
