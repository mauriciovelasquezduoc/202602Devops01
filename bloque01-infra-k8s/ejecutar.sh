#!/usr/bin/env bash
# ==================================================================
# GUIA 04 / BLOQUE 01 - Infraestructura Kubernetes consolidada
# Crea/valida rapidamente la infra base de guia-03 bloques 1, 2 y 3:
#   - VPC Multi-AZ + endpoints
#   - Cluster EKS + addons
#   - NodeGroup SPOT
#   - Metrics Server + CloudWatch logs
# Idempotente: si los recursos ya existen, valida y continua.
# ==================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUIA04_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
REPORT_FILE="$REPORT_DIR/infra-k8s-$(date +%Y%m%d-%H%M%S).md"

REGION="${REGION:-us-east-1}"
VPC_STACK="${VPC_STACK:-laboratorio-ep03-vpc}"
EKS_STACK="${EKS_STACK:-laboratorio-ep03-eks}"
CLUSTER_NAME="${CLUSTER_NAME:-laboratorio-ep03-eks}"
NODEGROUP_NAME="${NODEGROUP_NAME:-laboratorio-ep03-nodegroup}"
VPC_TEMPLATE="$SCRIPT_DIR/templates/vpc.yaml"
EKS_TEMPLATE="$SCRIPT_DIR/templates/cluster_eks.yaml"
SECRETS_FILE="$GUIA04_DIR/secrets.txt"

mkdir -p "$REPORT_DIR"

REPORT_LINES=()
STEP_STATUS=()
REPORT_WRITTEN=false


log() { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] ADVERTENCIA: $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ERROR: $*"; exit 1; }

add_report() { REPORT_LINES+=("$*"); }
record_step() { STEP_STATUS+=("| $1 | $2 | $3 |"); }

command_exists() { command -v "$1" >/dev/null 2>&1; }

load_secrets_if_present() {
  if [ -f "$SECRETS_FILE" ]; then
    log "Cargando variables desde $SECRETS_FILE"
    while IFS='=' read -r key value || [ -n "$key" ]; do
      [ -z "${key:-}" ] && continue
      [[ "$key" == \#* ]] && continue
      export "$key=$value"
    done < "$SECRETS_FILE"

    # Compatibilidad con secrets.txt en minusculas.
    [ -n "${aws_access_key_id:-}" ] && export AWS_ACCESS_KEY_ID="$aws_access_key_id"
    [ -n "${aws_secret_access_key:-}" ] && export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
    [ -n "${aws_session_token:-}" ] && export AWS_SESSION_TOKEN="$aws_session_token"
    [ -n "${AWS_REGION:-}" ] && export REGION="$AWS_REGION"
  fi
}

require_tools() {
  local missing=0
  for tool in aws kubectl; do
    if command_exists "$tool"; then
      log "Herramienta OK: $tool"
    else
      warn "Falta herramienta requerida: $tool"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || fail "Instala las herramientas faltantes antes de continuar."
}

aws_text() {
  aws "$@" --output text 2>/dev/null || true
}

stack_status() {
  aws_text cloudformation describe-stacks \
    --stack-name "$1" \
    --region "$REGION" \
    --query 'Stacks[0].StackStatus'
}

wait_stack_stable() {
  local stack="$1"
  local status=""
  log "Esperando stack estable: $stack"
  for _ in $(seq 1 90); do
    status="$(stack_status "$stack")"
    log "  $stack: ${status:-NO_EXISTE}"
    case "$status" in
      CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE|IMPORT_COMPLETE)
        return 0
        ;;
      *FAILED|ROLLBACK_COMPLETE|DELETE_COMPLETE|DELETE_IN_PROGRESS|ROLLBACK_IN_PROGRESS|UPDATE_ROLLBACK_IN_PROGRESS)
        return 1
        ;;
    esac
    sleep 20
  done
  return 1
}

stack_output() {
  local stack="$1"
  local key="$2"
  aws cloudformation describe-stacks \
    --stack-name "$stack" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" \
    --output text
}

ensure_vpc_stack() {
  log "Validando/creando VPC CloudFormation: $VPC_STACK"
  [ -f "$VPC_TEMPLATE" ] || fail "No existe template VPC: $VPC_TEMPLATE"

  local before
  before="$(stack_status "$VPC_STACK")"
  if [ -n "$before" ]; then
    log "Stack VPC ya existe con estado: $before"
  else
    log "Stack VPC no existe. Se creara."
  fi

  aws cloudformation deploy \
    --template-file "$VPC_TEMPLATE" \
    --stack-name "$VPC_STACK" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM

  wait_stack_stable "$VPC_STACK" || fail "El stack VPC no quedo estable. Revisa CloudFormation."

  local vpc_id public_a public_b app_a app_b data_a data_b
  vpc_id="$(stack_output "$VPC_STACK" VpcId)"
  public_a="$(stack_output "$VPC_STACK" PublicSubnetA)"
  public_b="$(stack_output "$VPC_STACK" PublicSubnetB)"
  app_a="$(stack_output "$VPC_STACK" PrivateAppSubnetA)"
  app_b="$(stack_output "$VPC_STACK" PrivateAppSubnetB)"
  data_a="$(stack_output "$VPC_STACK" PrivateDataSubnetA)"
  data_b="$(stack_output "$VPC_STACK" PrivateDataSubnetB)"

  record_step "VPC" "OK" "Stack $VPC_STACK, VPC $vpc_id"
  add_report "### VPC"
  add_report "- Stack: \`$VPC_STACK\`"
  add_report "- VPC: \`$vpc_id\`"
  add_report "- Public subnets: \`$public_a\`, \`$public_b\`"
  add_report "- Private app subnets: \`$app_a\`, \`$app_b\`"
  add_report "- Private data subnets: \`$data_a\`, \`$data_b\`"
}

validate_subnet_tags() {
  log "Validando tags EKS en subnets"
  local vpc_id
  vpc_id="$(stack_output "$VPC_STACK" VpcId)"

  aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0],Tags[?Key==`kubernetes.io/cluster/laboratorio-ep03-eks`].Value|[0],Tags[?Key==`kubernetes.io/role/elb`].Value|[0],Tags[?Key==`kubernetes.io/role/internal-elb`].Value|[0]]' \
    --output table

  record_step "Tags subnets" "OK" "Tags de LoadBalancer/EKS validados visualmente"
}

find_role_arn() {
  local pattern="$1"
  aws iam list-roles \
    --query "Roles[?contains(RoleName, '$pattern')].Arn | [0]" \
    --output text
}

ensure_eks_stack() {
  log "Validando/creando cluster EKS: $CLUSTER_NAME"
  [ -f "$EKS_TEMPLATE" ] || fail "No existe template EKS: $EKS_TEMPLATE"

  local vpc_id public_a public_b app_a app_b cluster_role node_role
  vpc_id="$(stack_output "$VPC_STACK" VpcId)"
  public_a="$(stack_output "$VPC_STACK" PublicSubnetA)"
  public_b="$(stack_output "$VPC_STACK" PublicSubnetB)"
  app_a="$(stack_output "$VPC_STACK" PrivateAppSubnetA)"
  app_b="$(stack_output "$VPC_STACK" PrivateAppSubnetB)"
  cluster_role="$(find_role_arn LabEksClusterRole)"
  node_role="$(find_role_arn LabEksNodeRole)"

  [ -n "$cluster_role" ] && [ "$cluster_role" != "None" ] || fail "No encontre rol IAM LabEksClusterRole"
  [ -n "$node_role" ] && [ "$node_role" != "None" ] || fail "No encontre rol IAM LabEksNodeRole"

  local before
  before="$(stack_status "$EKS_STACK")"
  if [ -n "$before" ]; then
    log "Stack EKS ya existe con estado: $before"
  else
    log "Stack EKS no existe. Se creara. Puede tardar 15-25 minutos."
  fi

  aws cloudformation deploy \
    --template-file "$EKS_TEMPLATE" \
    --stack-name "$EKS_STACK" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      VPCId="$vpc_id" \
      PublicSubnetA="$public_a" \
      PublicSubnetB="$public_b" \
      PrivateAppSubnetA="$app_a" \
      PrivateAppSubnetB="$app_b" \
      EksClusterRoleArn="$cluster_role" \
      EksNodeRoleArn="$node_role"

  wait_stack_stable "$EKS_STACK" || fail "El stack EKS no quedo estable. Revisa CloudFormation."

  wait_cluster_active
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
  record_step "Cluster EKS" "OK" "Cluster $CLUSTER_NAME activo y kubeconfig actualizado"
  add_report "### EKS"
  add_report "- Stack: \`$EKS_STACK\`"
  add_report "- Cluster: \`$CLUSTER_NAME\`"
  add_report "- Cluster role: \`$cluster_role\`"
  add_report "- Node role: \`$node_role\`"
}

wait_cluster_active() {
  log "Esperando cluster EKS ACTIVE: $CLUSTER_NAME"
  for _ in $(seq 1 90); do
    local status
    status="$(aws_text eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.status')"
    log "  Cluster: ${status:-NO_EXISTE}"
    if [ "$status" = "ACTIVE" ]; then
      return 0
    fi
    sleep 20
  done
  fail "El cluster $CLUSTER_NAME no llego a ACTIVE."
}

ensure_nodegroup_active() {
  log "Validando NodeGroup: $NODEGROUP_NAME"
  for _ in $(seq 1 90); do
    local status
    status="$(aws_text eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --region "$REGION" --query 'nodegroup.status')"
    log "  NodeGroup: ${status:-NO_EXISTE}"
    case "$status" in
      ACTIVE)
        record_step "NodeGroup" "OK" "$NODEGROUP_NAME ACTIVE"
        add_report "### NodeGroup"
        add_report "- Nombre: \`$NODEGROUP_NAME\`"
        add_report "- Estado: \`ACTIVE\`"
        return 0
        ;;
      CREATE_FAILED|DELETE_FAILED|DEGRADED)
        fail "NodeGroup en estado problematico: $status"
        ;;
    esac
    sleep 20
  done
  fail "El NodeGroup $NODEGROUP_NAME no llego a ACTIVE."
}

validate_kubernetes() {
  log "Validando Kubernetes"
  kubectl get nodes -o wide
  kubectl get pods -n kube-system -o wide
  record_step "Kubernetes" "OK" "Nodos y pods kube-system consultados"
}

validate_observability() {
  log "Validando observabilidad: metrics-server + CloudWatch"
  kubectl get apiservices | grep -E 'metrics|NAME' || true
  kubectl top nodes 2>/dev/null || warn "kubectl top nodes aun no entrega metricas; puede tardar unos minutos."
  aws logs describe-log-groups \
    --region "$REGION" \
    --query 'logGroups[?contains(logGroupName, `eks`)].logGroupName' \
    --output table 2>/dev/null || true

  record_step "Observabilidad" "OK" "Metrics Server/CloudWatch validados o en propagacion"
  add_report "### Observabilidad"
  add_report "- Metrics Server: addon EKS incluido en el template."
  add_report "- CloudWatch: logging EKS habilitado en el cluster."
}

write_report() {
  local account
  account="$(aws_text sts get-caller-identity --query Account)"

  {
    echo "# Reporte Infra K8s"
    echo ""
    echo "Generado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Contexto"
    echo ""
    echo "- AWS Account: \`${account:-desconocida}\`"
    echo "- Region: \`$REGION\`"
    echo "- VPC Stack: \`$VPC_STACK\`"
    echo "- EKS Stack: \`$EKS_STACK\`"
    echo "- Cluster: \`$CLUSTER_NAME\`"
    echo "- NodeGroup: \`$NODEGROUP_NAME\`"
    echo ""
    echo "## Estado de pasos"
    echo ""
    echo "| Paso | Estado | Detalle |"
    echo "|---|---|---|"
    for line in "${STEP_STATUS[@]}"; do echo "$line"; done
    echo ""
    printf '%s\n' "${REPORT_LINES[@]}"
    echo ""
    echo "## Evidencia sugerida"
    echo ""
    echo '```bash'
    echo "aws cloudformation describe-stacks --region $REGION --stack-name $VPC_STACK --query 'Stacks[0].StackStatus' --output text"
    echo "aws cloudformation describe-stacks --region $REGION --stack-name $EKS_STACK --query 'Stacks[0].StackStatus' --output text"
    echo "aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query 'cluster.{name:name,status:status,version:version,endpoint:endpoint}' --output table"
    echo "aws eks describe-nodegroup --region $REGION --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --query 'nodegroup.{name:nodegroupName,status:status,capacity:capacityType,desired:scalingConfig.desiredSize}' --output table"
    echo "kubectl get nodes -o wide"
    echo "kubectl get pods -n kube-system -o wide"
    echo "kubectl top nodes"
    echo '```'
  } > "$REPORT_FILE"

  REPORT_WRITTEN=true
  log "Reporte generado: $REPORT_FILE"
}

on_exit() {
  local code=$?
  if [ "$code" -ne 0 ] && [ "${REPORT_WRITTEN:-false}" != true ]; then
    STEP_STATUS+=("| Ejecucion | ERROR | Codigo de salida $code |")
    write_report >/dev/null 2>&1 || true
    echo "Reporte parcial: $REPORT_FILE"
  fi
}

trap on_exit EXIT

main() {
  echo "============================================================="
  echo " GUIA 04 - BLOQUE 01: Infraestructura Kubernetes consolidada"
  echo "============================================================="
  echo ""

  load_secrets_if_present
  require_tools

  log "Validando credenciales AWS"
  aws sts get-caller-identity >/dev/null || fail "AWS CLI no tiene credenciales validas."
  record_step "Credenciales AWS" "OK" "STS respondio correctamente"

  ensure_vpc_stack
  validate_subnet_tags
  ensure_eks_stack
  ensure_nodegroup_active
  validate_kubernetes
  validate_observability
  write_report

  echo ""
  echo "============================================================="
  echo " INFRA K8S LISTA"
  echo "============================================================="
  echo "Reporte: $REPORT_FILE"
  echo ""
}

main "$@"
