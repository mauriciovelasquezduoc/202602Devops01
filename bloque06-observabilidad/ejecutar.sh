#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - OBSERVABILIDAD / Preparación del entorno
#
# ¿QUE HACE? (idempotente: puedes ejecutarlo las veces que quieras)
#   1. Valida que el cluster EKS y la app del bloque03 estén corriendo
#   2. Descubre los recursos reales (nodos, LoadBalancer)
#   3. Crea topic SNS para notificaciones (opcional, con email)
#   4. Crea ALARMAS en CloudWatch:
#        ep02-backend-salud   : métrica personalizada SaludBackend < 1
#        ep02-backend-pods    : métrica personalizada PodsActivos < 1
#        ep02-cpu-nodo-alta   : CPU del nodo EC2 >= 60%
#        ep02-elb-5xx         : errores 5XX del balanceador >= 5
#
#   Las demos (demo-1, demo-2) dispararán estas alarmas en vivo.
# ==================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUIA04_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_FILE="$GUIA04_DIR/secrets.txt"
REPORT_DIR="$SCRIPT_DIR/reports"
REPORT_FILE="$REPORT_DIR/bloque06-$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$REPORT_DIR"

REGION="${REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-laboratorio-ep02-eks}"
NODEGROUP_NAME="${NODEGROUP_NAME:-laboratorio-ep02-nodegroup}"
NAMESPACE="ep02"
APP="ep02-backend"
SNS_TOPIC="ep02-alertas"
CW_NAMESPACE="Ep02/Microservicio"

# Colores
AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${AZUL}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${VERDE}  ✔ $*${NC}"; }
warn() { echo -e "${AMAR}  ⚠ $*${NC}"; }
fail() { echo -e "${ROJO}  ✘ $*${NC}"; exit 1; }
titulo() { echo -e "\n${AZUL}============================================================${NC}"; echo -e "${AZUL} $*${NC}"; echo -e "${AZUL}============================================================${NC}"; }

REPORT_LINES=()
add_report() { REPORT_LINES+=("$*"); }

# Cargar credenciales/region desde secrets.txt (patrón del lab)
if [ -f "$SECRETS_FILE" ]; then
  log "Cargando variables desde secrets.txt"
  while IFS='=' read -r key value || [ -n "$key" ]; do
    [ -z "${key:-}" ] && continue
    [[ "$key" == \#* ]] && continue
    export "$key=$value"
  done < "$SECRETS_FILE"
  [ -n "${aws_access_key_id:-}" ]      && export AWS_ACCESS_KEY_ID="$aws_access_key_id"
  [ -n "${aws_secret_access_key:-}" ]  && export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
  [ -n "${aws_session_token:-}" ]      && export AWS_SESSION_TOKEN="$aws_session_token"
  [ -n "${AWS_REGION:-}" ]             && export REGION="$AWS_REGION"
fi

# ==================================================================
titulo "[0/5] Validaciones previas"
# ==================================================================
for tool in aws kubectl jq curl; do
  command -v "$tool" >/dev/null 2>&1 || fail "Falta la herramienta: $tool"
  ok "Herramienta OK: $tool"
done

aws sts get-caller-identity >/dev/null 2>&1 || fail "No hay credenciales AWS activas. Abre 'AWS Details' en Academy y vuelve a iniciar el contenedor."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ok "Sesión AWS válida — cuenta $ACCOUNT_ID, región $REGION"

CLUSTER_STATE="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" --query 'cluster.status' --output text 2>/dev/null || echo 'NO_EXISTE')"
[ "$CLUSTER_STATE" = "ACTIVE" ] || fail "El cluster $CLUSTER_NAME no está ACTIVE (estado: $CLUSTER_STATE). Ejecuta primero el bloque01."
ok "Cluster EKS $CLUSTER_NAME ACTIVE"

kubectl get nodes --no-headers 2>/dev/null | grep -q Ready || fail "No hay nodos Ready. Revisa el bloque01."
ok "Nodos Ready: $(kubectl get nodes --no-headers | grep -c Ready)"

kubectl get deploy "$APP" -n "$NAMESPACE" >/dev/null 2>&1 || fail "No existe deploy/$APP en el namespace $NAMESPACE. Aplica primero el bloque03."
BACKEND_OK=$(kubectl get pods -n "$NAMESPACE" -l "app=$APP" --no-headers 2>/dev/null | grep -c "1/1" || true)
[ "${BACKEND_OK:-0}" -ge 1 ] || fail "El backend no tiene pods Ready. Verifica con: kubectl get pods -n $NAMESPACE"
ok "Backend $APP corriendo ($BACKEND_OK pod(s) Ready)"

kubectl get hpa -n "$NAMESPACE" >/dev/null 2>&1 && ok "HPA visibles (metrics-server operativo)" || warn "No hay HPA: la demo de carga no podrá escalar. Revisa el bloque03."

# ==================================================================
titulo "[1/5] Descubriendo recursos reales"
# ==================================================================
# Nodos EC2: en AWS Academy 'aws ec2 describe-instances' está negado por SCP,
# así que obtenemos los instance IDs desde Kubernetes (providerID).
NODE_IDS=()
while read -r pid; do
  id="${pid##*/}"; id="${id%%/*}"          # aws:///i-0abc/us-east-1a -> i-0abc
  [ -n "$id" ] && NODE_IDS+=("$id")
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}')
for id in "${NODE_IDS[@]:-}"; do [ -n "$id" ] && ok "Nodo EC2 detectado: $id"; done
add_report "Nodos EC2: ${NODE_IDS[*]:-ninguno}"

# LoadBalancer público del frontend
LB_DNS="$(kubectl get svc "$NAMESPACE-frontend" -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [ -n "$LB_DNS" ]; then
  ok "LoadBalancer del frontend: $LB_DNS"
  add_report "LB DNS: $LB_DNS"
  # Nombre del Classic LoadBalancer (dimensión que exige la alarma AWS/ELB)
  ELB_NAME="$(aws elb describe-load-balancers --region "$REGION" \
    --query "LoadBalancerDescriptions[?DNSName=='$LB_DNS'].LoadBalancerName" \
    --output text 2>/dev/null || true)"
  [ -z "$ELB_NAME" ] || [ "$ELB_NAME" = "None" ] && ELB_NAME=""
  [ -n "$ELB_NAME" ] && ok "Nombre del CLB para CloudWatch: $ELB_NAME" || warn "No se resolvió el nombre del CLB (alarma 5XX se omitirá)."
  add_report "CLB: ${ELB_NAME:-no detectado}"
else
  warn "El frontend no tiene LoadBalancer asignado todavía."
fi

# ==================================================================
titulo "[2/5] Notificaciones: topic SNS (opcional)"
# ==================================================================
# Una ALARMA avisa por SNS. Sin SNS la alarma igual cambia de estado y se
# ve en consola; con SNS además llega un correo.
SNS_ARN=""
TOPIC_ARN="$(aws sns create-topic --region "$REGION" --name "$SNS_TOPIC" --output text --query 'TopicArn' 2>/dev/null || true)"
if [ -n "$TOPIC_ARN" ]; then
  SNS_ARN="$TOPIC_ARN"
  ok "Topic SNS: $TOPIC_ARN"
  add_report "SNS topic: $TOPIC_ARN"
  echo ""
  echo -e "${AMAR}  Para recibir un CORREO cuando salte una alarma, ingresa tu email.${NC}"
  echo -e "${AMAR}  (Enter para omitir. La suscripción hay que confirmarla desde el correo.)${NC}"
  read -r -p "  Email (opcional): " ALERT_EMAIL
  if [ -n "${ALERT_EMAIL:-}" ]; then
    if aws sns subscribe --region "$REGION" --topic-arn "$TOPIC_ARN" \
         --protocol email --notification-endpoint "$ALERT_EMAIL" >/dev/null 2>&1; then
      ok "Suscripción enviada a $ALERT_EMAIL — CONFÍRMALA desde tu correo para recibir avisos."
      add_report "Suscripción email: $ALERT_EMAIL (pendiente de confirmar)"
    else
      warn "No se pudo suscribir el email (permisos SNS). Las alarmas seguirán visibles en consola."
    fi
  fi
else
  warn "No se pudo crear el topic SNS (permisos). Las alarmas seguirán visibles en consola."
fi

# ==================================================================
titulo "[3/5] Publicando la métrica personalizada por primera vez"
# ==================================================================
# Una alarma sobre una métrica sin datos queda en INSUFFICIENT_DATA.
# Publicamos ahora para que empiece con datos reales.
bash "$SCRIPT_DIR/push-metrica.sh" || warn "push-metrica falló; las alarmas quedarán en INSUFFICIENT_DATA hasta el primer dato."
add_report "Primera publicación de Ep02/Microservicio realizada"

# ==================================================================
titulo "[4/5] Creando alarmas en CloudWatch"
# ==================================================================
crear_alarma() {  # $1 nombre | resto: argumentos put-metric-alarm
  local nombre="$1"; shift
  local acciones=()
  [ -n "$SNS_ARN" ] && acciones=(--alarm-actions "$SNS_ARN")
  if aws cloudwatch put-metric-alarm --region "$REGION" --alarm-name "$nombre" \
       ${acciones[@]+"${acciones[@]}"} "$@" >/dev/null 2>&1; then
    ok "Alarma creada/actualizada: $nombre"
    add_report "Alarma: $nombre"
  else
    warn "No se pudo crear '$nombre' (permisos CloudWatch en Academy). Se omitirá."
  fi
}

# --- Alarma 1: salud del microservicio (MÉTRICA PERSONALIZADA) ---
# Se dispara por un CERO MEDIDO (salud=0 publicado durante una falla real).
# Con notBreaching evitamos falsas alarmas cuando simplemente no se publica.
crear_alarma "ep02-backend-salud" \
  --namespace "$CW_NAMESPACE" --metric-name SaludBackend \
  --dimensions Deployment="$APP" \
  --statistic Minimum --threshold 1 --comparison-operator LessThanThreshold \
  --period 60 --evaluation-periods 1 \
  --treat-missing-data notBreaching \
  --alarm-description "El backend midió salud=0: /actuator/health no responde (métrica personalizada)"

# --- Alarma 2: pods del backend bajo el mínimo (MÉTRICA PERSONALIZADA) ---
# El HPA pide min=1 réplica; si medimos 0 pods Ready algo está mal.
crear_alarma "ep02-backend-pods" \
  --namespace "$CW_NAMESPACE" --metric-name PodsActivos \
  --dimensions Deployment="$APP" \
  --statistic Minimum --threshold 1 --comparison-operator LessThanThreshold \
  --period 60 --evaluation-periods 1 \
  --treat-missing-data notBreaching \
  --alarm-description "Backend con menos pods Ready que el mínimo del HPA (1)"

# --- Alarma 3: CPU del nodo EC2 (MÉTRICA AUTOMÁTICA) ---
# La publica EC2 por nosotros. Umbral didáctico: 60% sostenido 2 minutos.
for id in "${NODE_IDS[@]:-}"; do
  [ -z "$id" ] && continue
  crear_alarma "ep02-cpu-nodo-alta-${id: -6}" \
    --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions InstanceId="$id" \
    --statistic Average --threshold 60 --comparison-operator GreaterThanOrEqualToThreshold \
    --period 60 --evaluation-periods 2 \
    --alarm-description "Nodo EC2 saturado (CPU promedio >= 60% por 2 minutos)"
done

# --- Alarma 4: errores 5XX del balanceador (MÉTRICA AUTOMÁTICA) ---
if [ -n "${ELB_NAME:-}" ]; then
  crear_alarma "ep02-elb-5xx" \
    --namespace AWS/ELB --metric-name HTTPCode_ELB_5XX \
    --dimensions LoadBalancerName="$ELB_NAME" \
    --statistic Sum --threshold 5 --comparison-operator GreaterThanOrEqualToThreshold \
    --period 60 --evaluation-periods 1 \
    --alarm-description "El balanceador reporta 5+ errores 5XX por minuto (backend caído o saturado)"
fi

# ==================================================================
titulo "[5/5] Estado inicial de las alarmas"
# ==================================================================
aws cloudwatch describe-alarms --region "$REGION" \
  --query 'MetricAlarms[?starts_with(AlarmName, `ep02`)].[AlarmName,StateValue,MetricName]' \
  --output table 2>/dev/null || warn "No se pudo listar alarmas."

cat > "$REPORT_FILE" <<EOF
# Bloque 06 — Preparación de Observabilidad
Fecha: $(date '+%Y-%m-%d %H:%M:%S')  |  Región: $REGION  |  Cluster: $CLUSTER_NAME

| Elemento | Estado | Detalle |
|---|---|---|
$(for l in ${REPORT_LINES[@]+"${REPORT_LINES[@]}"}; do [ -n "$l" ] && echo "| $l | OK | - |"; done)

Alarmas esperadas: ep02-backend-salud, ep02-backend-pods, ep02-cpu-nodo-alta-*, ep02-elb-5xx
EOF
ok "Reporte guardado en: $REPORT_FILE"

echo ""
echo -e "${VERDE}Entorno listo. Continúa con la guía:${NC}"
echo -e "${VERDE}  bash demo-1-auto-reparacion.sh   # borrar pods y ver la reconstrucción${NC}"
echo -e "${VERDE}  bash demo-2-prueba-carga.sh      # carga para escalar HPA y disparar alarmas${NC}"
echo -e "${VERDE}  bash demo-3-observatorio.sh      # ver el estado de las alarmas en vivo${NC}"
