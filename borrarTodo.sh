#!/bin/bash
# ==================================================================
# borrarTodo.sh — LIMPIEZA TOTAL del laboratorio
# ==================================================================
# Borra TODO lo creado en AWS (y opcionalmente GitHub + local):
#   - Namespace "ep02" (Pods, Services, Deployments, HPA)
#   - Load Balancers (ELB clásicos y v2/NLB) huérfanos en la VPC
#   - Security Groups k8s-* / eks-cluster-sg huérfanos
#   - Stack CloudFormation "laboratorio-ep02-eks" (cluster + nodegroup + addons)
#   - Stack CloudFormation "laboratorio-ep02-vpc" (VPC + subnets + endpoints)
#   - Repositorios ECR (todo lo que empiece con "ep02")
#   - CloudWatch Log Groups del cluster EKS
#   - Repositorios en GitHub con "ep02" en el nombre
#   - Contexto de kubeconfig + known_hosts de github.com
#
# CLAVE: los ELB y los SG k8s-* deben borrarse ANTES que la VPC; si no,
# CloudFormation falla con DELETE_FAILED (ENIs/SG en uso).
#
# MODO VERBOSO: cada comando aws/kubectl se muestra antes de ejecutarse,
# su salida se imprime, el borrado de stacks se sondea cada 30s mostrando
# el estado, y ante un DELETE_FAILED se listan los recursos culpables.
#
# Uso:
#   bash borrarTodo.sh          # pide confirmación
#   bash borrarTodo.sh -y       # sin confirmación
#
# Credenciales: se leen de ./secrets.txt (o del entorno).
# ==================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.txt"

REGION="us-east-1"
CLUSTER_NAME="laboratorio-ep02-eks"
NAMESPACE="ep02"
STACK_VPC="laboratorio-ep02-vpc"
STACK_EKS="laboratorio-ep02-eks"
NODEGROUP_NAME="laboratorio-ep02-nodegroup"
ECR_PREFIX="ep02"
GH_NAME_FILTER="ep02"

ROJO='\033[0;31m'; VERDE='\033[0;32m'; AMAR='\033[1;33m'; AZUL='\033[0;34m'; NC='\033[0m'
log()  { echo -e "$*"; }
ok()   { echo -e "  ${VERDE}OK  $*${NC}"; }
warn() { echo -e "  ${AMAR}$*${NC}"; }
err()  { echo -e "  ${ROJO}$*${NC}"; }
# Muestra en pantalla el comando que se va a ejecutar (modo verboso)
show_cmd() { log "  ${AZUL}→ \$ ${*}${NC}"; }

# ── Cargar credenciales de secrets.txt ──────────────────────────────────────
if [ -f "$SECRETS_FILE" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="${key//[[:space:]]/}"; [ -z "$key" ] && continue; [[ "$key" == \#* ]] && continue
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    [ -z "$value" ] && continue; export "$key=$value"
  done < "$SECRETS_FILE"
  [ -n "${aws_access_key_id:-}" ]     && export AWS_ACCESS_KEY_ID="$aws_access_key_id"
  [ -n "${aws_secret_access_key:-}" ] && export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
  [ -n "${aws_session_token:-}" ]     && export AWS_SESSION_TOKEN="$aws_session_token"
  [ -n "${AWS_REGION:-}" ]            && REGION="$AWS_REGION"
fi

log ""
log "${AZUL}============================================================"
log " LIMPIEZA TOTAL DEL LABORATORIO"
log "============================================================${NC}"
log "${AMAR}⚠  ELIMINA en AWS: VPC, EKS, NodeGroup, ELBs, SGs, ECR, logs."
log "   y en GitHub: repos con '${GH_NAME_FILTER}'. NO se puede deshacer.${NC}"
log ""

if [ "${1:-}" != "-y" ] && [ "${1:-}" != "--yes" ]; then
  read -r -p "  ¿Continuar? (s/N): " CONFIRM
  [ "$CONFIRM" = "s" ] || [ "$CONFIRM" = "S" ] || { log "${ROJO}  Cancelado.${NC}"; exit 0; }
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
stack_status() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$REGION" \
    --query "Stacks[0].StackStatus" --output text 2>/dev/null || true
}

# Muestra los recursos que provocaron el DELETE_FAILED
show_stack_errors() {
  local stack="$1"
  show_cmd aws cloudformation describe-stack-events --stack-name "$stack" \
    --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceStatusReason]"
  aws cloudformation describe-stack-events --stack-name "$stack" --region "$REGION" \
    --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceStatusReason]" \
    --output text 2>/dev/null | head -10 | sed 's/^/      /' || true
}

delete_cf_stack() {
  local stack="$1" tries=0 status elapsed polls=0 out
  local max_polls=60   # 60 x 30s = timeout de seguridad a los 30 min
  status="$(stack_status "$stack")"
  if [ -z "$status" ]; then warn "Stack $stack no existe"; return 0; fi
  warn "Estado inicial del stack: $status"
  while :; do
    show_cmd aws cloudformation delete-stack --stack-name "$stack" --region "$REGION"
    if out="$(aws cloudformation delete-stack --stack-name "$stack" --region "$REGION" 2>&1)"; then
      ok "delete-stack enviado"
    else
      warn "delete-stack rechazado: $out"
    fi
    log "  ${AMAR}Esperando borrado (sondeo cada 30s)…${NC}"
    elapsed=0; polls=0
    while :; do
      sleep 30; elapsed=$((elapsed + 30)); polls=$((polls + 1))
      status="$(stack_status "$stack")"
      if [ -z "$status" ] || [ "$status" = "DELETE_COMPLETE" ]; then
        ok "Stack $stack eliminado (${elapsed}s de espera)"; return 0
      fi
      warn "  … ${elapsed}s — estado: $status"
      case "$status" in *DELETE_FAILED*|*ROLLBACK*) break ;; esac
      if [ "$polls" -ge "$max_polls" ]; then
        err "Timeout de 30 min esperando $stack (estado: $status)"; break
      fi
    done
    tries=$((tries + 1))
    err "No se pudo borrar $stack (estado: $status), intento $tries/3"
    show_stack_errors "$stack"
    [ "$tries" -ge 3 ] && return 1
    sleep 15
  done
}

# Borra ELBs (v2 + clásicos) y SGs k8s-* de la VPC (liberan ENIs/SGs que
# bloquean el borrado de la VPC).
purge_vpc_dependencies() {
  local vpc_id="$1"
  [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ] || { warn "Sin VPC ID; salto purga"; return 0; }

  local arn lb sg out lbs_v2 lbs_cl sgs
  show_cmd aws elbv2 describe-load-balancers --region "$REGION" --query "…VpcId=='$vpc_id'…"
  lbs_v2="$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" --output text 2>/dev/null || true)"
  if [ -n "$lbs_v2" ] && [ "$lbs_v2" != "None" ]; then
    for arn in $lbs_v2; do
      show_cmd aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
      if out="$(aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$REGION" 2>&1)"; then
        ok "LBv2 borrado: $arn"
      else
        warn "no se pudo borrar $arn: $out"
      fi
    done
  else
    warn "sin ELBs v2 en la VPC $vpc_id"
  fi
  show_cmd aws elb describe-load-balancers --region "$REGION" --query "…VPCId=='$vpc_id'…"
  lbs_cl="$(aws elb describe-load-balancers --region "$REGION" \
      --query "LoadBalancerDescriptions[?VPCId=='$vpc_id'].LoadBalancerName" --output text 2>/dev/null || true)"
  if [ -n "$lbs_cl" ] && [ "$lbs_cl" != "None" ]; then
    for lb in $lbs_cl; do
      show_cmd aws elb delete-load-balancer --load-balancer-name "$lb"
      if out="$(aws elb delete-load-balancer --load-balancer-name "$lb" --region "$REGION" 2>&1)"; then
        ok "ELB clásico borrado: $lb"
      else
        warn "no se pudo borrar $lb: $out"
      fi
    done
  else
    warn "sin ELBs clásicos en la VPC $vpc_id"
  fi
  warn "Esperando 30s a que se liberen las ENIs de los LB (se liberan de forma asíncrona)…"
  sleep 30

  show_cmd aws ec2 describe-security-groups --region "$REGION" --filters "vpc-id=$vpc_id" "k8s-*/eks-cluster-sg"
  sgs="$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc_id" \
      --query "SecurityGroups[?GroupName!='default' && (starts_with(GroupName,'k8s-') || starts_with(GroupName,'eks-cluster-sg'))].GroupId" \
      --output text 2>/dev/null || true)"
  if [ -n "$sgs" ] && [ "$sgs" != "None" ]; then
    for sg in $sgs; do
      show_cmd aws ec2 delete-security-group --group-id "$sg"
      if out="$(aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>&1)"; then
        ok "SG borrado: $sg"
      else
        warn "SG $sg en uso (se reintentará al borrar la VPC): $out"
      fi
    done
  else
    warn "sin SGs k8s-*/eks-cluster-sg en la VPC $vpc_id"
  fi
}

# ── 0. Conectividad AWS ─────────────────────────────────────────────────────
log "${AZUL}[0/10] Validando conectividad AWS…${NC}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [ -z "$ACCOUNT_ID" ]; then
  err "Sin conexión a AWS. Renueva credenciales (AWS Academy → Start Lab) y actualiza secrets.txt."
  exit 1
fi
ok "AWS OK — account=$ACCOUNT_ID region=$REGION"
log ""

# VPC ID (antes de borrar el stack)
VPC_ID="$(aws cloudformation describe-stacks --stack-name "$STACK_VPC" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" --output text 2>/dev/null || true)"

# ── 1. kubeconfig + namespace ep02 ──────────────────────────────────────────
log "${AZUL}[1/10] Borrando namespace $NAMESPACE…${NC}"
CLUSTER_STATUS="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.status' --output text 2>/dev/null || echo NOEXISTE)"
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
fi
if kubectl get namespace "$NAMESPACE" --request-timeout=15s >/dev/null 2>&1; then
  for kind in hpa deployment svc pod; do
    show_cmd kubectl delete "$kind" -n "$NAMESPACE" --all --grace-period=0 --force
    kubectl delete "$kind" -n "$NAMESPACE" --all --grace-period=0 --force --request-timeout=15s 2>&1 | sed 's/^/    /' || true
  done
  show_cmd kubectl delete namespace "$NAMESPACE" --grace-period=0 --force
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --grace-period=0 --force --request-timeout=15s 2>&1 | sed 's/^/    /' || true
  log "  esperando terminación del namespace (hasta 60s)…"
  local_terminated=""
  for _ in $(seq 1 30); do
    if ! kubectl get namespace "$NAMESPACE" --request-timeout=15s >/dev/null 2>&1; then local_terminated=1; printf '\n'; break; fi
    printf '.'; sleep 2
  done
  [ -z "$local_terminated" ] && printf '\n'
  kubectl get namespace "$NAMESPACE" --request-timeout=15s >/dev/null 2>&1 && warn "Namespace aún existe (se resolverá al borrar el cluster)" || ok "Namespace $NAMESPACE eliminado"
else
  warn "Namespace $NAMESPACE no existe"
fi
log ""

# ── 2. Load Balancers + SGs huérfanos (antes de tocar VPC) ───────────────────
log "${AZUL}[2/10] Borrando ELBs y SGs k8s-* huérfanos en la VPC…${NC}"
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  # La VPC pudo no existir aún; intentar recalcular
  VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=laboratorio-ep02" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
fi
purge_vpc_dependencies "${VPC_ID:-}"
log ""

# ── 3. Stack EKS (cluster + nodegroup + addons) ─────────────────────────────
log "${AZUL}[3/10] Borrando stack $STACK_EKS (10-15 min)…${NC}"
delete_cf_stack "$STACK_EKS" || err "El stack $STACK_EKS no se pudo eliminar (revisa eventos)"
log ""

# ── 4. Dependencias restantes de la VPC (SGs/ELBs que quedaron) ──────────────
log "${AZUL}[4/10] Purgando dependencias restantes de la VPC…${NC}"
purge_vpc_dependencies "${VPC_ID:-}"
log ""

# ── 5. Stack VPC ────────────────────────────────────────────────────────────
log "${AZUL}[5/10] Borrando stack $STACK_VPC…${NC}"
delete_cf_stack "$STACK_VPC" || err "El stack $STACK_VPC no se pudo eliminar (probable ENI/SG en uso; reintenta)"
log ""

# ── 6. Repositorios ECR (todo lo que empiece con 'ep02') ────────────────────
log "${AZUL}[6/10] Borrando repositorios ECR (prefijo '$ECR_PREFIX')…${NC}"
ECR_REPOS="$(aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?starts_with(repositoryName, '$ECR_PREFIX')].repositoryName" --output text 2>/dev/null || true)"
if [ -n "$ECR_REPOS" ] && [ "$ECR_REPOS" != "None" ]; then
  for repo in $ECR_REPOS; do
    show_cmd aws ecr delete-repository --repository-name "$repo" --force
    if out="$(aws ecr delete-repository --repository-name "$repo" --region "$REGION" --force 2>&1)"; then
      ok "$repo eliminado"
    else
      err "$repo: error al borrar — $out"
    fi
  done
else
  warn "No hay repos ECR con prefijo '$ECR_PREFIX'"
fi
log ""

# ── 7. CloudWatch Log Groups del cluster ────────────────────────────────────
log "${AZUL}[7/10] Borrando CloudWatch Log Groups…${NC}"
LOG_GROUPS="$(aws logs describe-log-groups --region "$REGION" \
  --query "logGroups[?contains(logGroupName, '/aws/eks/$CLUSTER_NAME')].logGroupName" --output text 2>/dev/null || true)"
if [ -n "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
  for lg in $LOG_GROUPS; do
    show_cmd aws logs delete-log-group --log-group-name "$lg"
    if out="$(aws logs delete-log-group --log-group-name "$lg" --region "$REGION" 2>&1)"; then
      ok "log group borrado: $lg"
    else
      warn "no se pudo borrar $lg: $out"
    fi
  done
else
  warn "No hay log groups de $CLUSTER_NAME"
fi
log ""

# ── 8. Repositorios en GitHub (nombre contiene 'ep02') ──────────────────────
log "${AZUL}[8/10] Borrando repositorios GitHub (contienen '$GH_NAME_FILTER')…${NC}"
USER_GITHUB="$(gh api user --jq '.login' 2>/dev/null || echo "")"
if [ -n "$USER_GITHUB" ]; then
  log "  Usuario GitHub: $USER_GITHUB"
  GH_REPOS="$(gh repo list "$USER_GITHUB" --limit 300 --json name \
    --jq ".[] | select(.name | test(\"$GH_NAME_FILTER\"; \"i\")) | .name" 2>/dev/null || true)"
  if [ -n "$GH_REPOS" ]; then
    while read -r repo; do
      [ -n "$repo" ] || continue
      gh repo delete "$USER_GITHUB/$repo" --yes >/dev/null 2>&1 \
        && ok "$USER_GITHUB/$repo eliminado" || err "$USER_GITHUB/$repo: error al borrar"
    done <<< "$GH_REPOS"
  else
    warn "No hay repos con '$GH_NAME_FILTER'"
  fi
else
  warn "No se pudo obtener usuario GitHub (gh no autenticado). Se omite."
fi
log ""

# ── 9. Archivos locales generados ───────────────────────────────────────────
log "${AZUL}[9/10] Limpiando archivos locales generados…${NC}"
rm -f "$SCRIPT_DIR/bloque02-ecr/resultado-ecr.yaml" 2>/dev/null && ok "resultado-ecr.yaml eliminado" || true
rm -rf "$SCRIPT_DIR/bloque03-k8s/output" 2>/dev/null && ok "bloque03-k8s/output eliminado" || true
log ""

# ── 10. kubeconfig + known_hosts ────────────────────────────────────────────
log "${AZUL}[10/10] Limpiando kubeconfig y known_hosts…${NC}"
CLUSTER_ARN="arn:aws:eks:$REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME"
kubectl config delete-context "$CLUSTER_ARN" >/dev/null 2>&1 || true
kubectl config delete-cluster "$CLUSTER_ARN" >/dev/null 2>&1 || true
kubectl config delete-user    "$CLUSTER_ARN" >/dev/null 2>&1 || true
kubectl config unset "contexts.$CLUSTER_NAME" >/dev/null 2>&1 || true
kubectl config unset "clusters.$CLUSTER_NAME" >/dev/null 2>&1 || true
ok "kubeconfig limpiado"
ssh-keygen -R github.com >/dev/null 2>&1 || true
ok "known_hosts de github.com limpiado"
log ""

# ── Verificación ────────────────────────────────────────────────────────────
log "${AZUL}===== VERIFICACIÓN =====${NC}"
ERRORES=0
for stack in "$STACK_EKS" "$STACK_VPC"; do
  st="$(stack_status "$stack")"
  if [ -n "$st" ]; then err "Stack $stack: $st"; ERRORES=$((ERRORES + 1)); else ok "Stack $stack: eliminado"; fi
done
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  if aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" >/dev/null 2>&1; then
    err "VPC $VPC_ID: aún existe"; ERRORES=$((ERRORES + 1))
  else
    ok "VPC: eliminada"
  fi
fi
REMAIN_ECR="$(aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?starts_with(repositoryName, '$ECR_PREFIX')].repositoryName" --output text 2>/dev/null || true)"
if [ -n "$REMAIN_ECR" ] && [ "$REMAIN_ECR" != "None" ]; then
  err "ECR restantes: $REMAIN_ECR"; ERRORES=$((ERRORES + 1))
else
  ok "ECR: sin repos '$ECR_PREFIX*'"
fi

log ""
log "${AZUL}============================================================${NC}"
if [ "$ERRORES" -eq 0 ]; then
  log "${VERDE} LIMPIEZA COMPLETA — no deberían quedar recursos cobrables${NC}"
else
  log "${AMAR} Limpieza con $ERRORES pendiente(s). Revisa los mensajes y reintenta.${NC}"
fi
log "${AZUL}============================================================${NC}"
log ""
