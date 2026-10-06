#!/bin/bash
# ==================================================================
# ETAPA 12 — Limpieza total del laboratorio
# ==================================================================
# Elimina TODO lo creado en las etapas 01-11:
#   - Namespace "ep03" (Pods, Services, Deployments, HPA, ELB)
#   - Stack CloudFormation "laboratorio-ep03-eks" (cluster + nodegroup + addons)
#   - Stack CloudFormation "laboratorio-ep03-vpc" (VPC + subnets + endpoints)
#   - Repositorios ECR (ep03-db, ep03-backend, ep03-frontend)
#   - Repositorios GitHub (202601_ep03_db, backend, frontend)
#   - Directorios locales clonados
#   - CloudWatch Log Groups del cluster EKS
#   - Contexto de kubeconfig
#   - known_hosts de github.com
#
# Uso:
#   bash ejecutar.sh
# ==================================================================

REGION="us-east-1"
CLUSTER_NAME="laboratorio-ep03-eks"
NAMESPACE="ep03"
STACK_VPC="laboratorio-ep03-vpc"
STACK_EKS="laboratorio-ep03-eks"
NODEGROUP_NAME="laboratorio-ep03-nodegroup"

# ──────────────────────────────────────────────────────────────────
# Determinar SCRIPT_DIR de forma portable (macOS / Linux)
# ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────────────────────────────
# Colores para output
# ──────────────────────────────────────────────────────────────────
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${AZUL}=============================================================${NC}"
echo -e "${AZUL} ETAPA 12 — Limpieza total del laboratorio${NC}"
echo -e "${AZUL}=============================================================${NC}"
echo ""
echo -e "${AMARILLO}⚠  Esto ELIMINARÁ todos los recursos creados en las etapas 01-11.${NC}"
echo -e "${AMARILLO}⚠  Incluye: VPC, Cluster EKS, NodeGroup, ECR, GitHub repos, K8s resources.${NC}"
echo -e "${AMARILLO}⚠  Esta acción NO se puede deshacer.${NC}"
echo ""
read -r -p "  ¿Estás seguro de continuar? (s/N): " CONFIRM
echo ""

if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
  echo -e "${ROJO}  ❌ Operación cancelada.${NC}"
  exit 0
fi

# ==================================================================
# 0. Validar conectividad AWS
# ==================================================================
echo -e "${AZUL}[0/9] Validando conectividad AWS...${NC}"
if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  echo -e "${ROJO}  ❌ ERROR: Sin conexión a AWS.${NC}"
  echo "     Ejecuta 'aws configure' o renueva tus credenciales AWS Academy."
  exit 1
fi
echo -e "${VERDE}  ✅ Conectado a AWS — Account ID: $ACCOUNT_ID${NC}"
echo ""

# ==================================================================
# 1. Forzar conexión al cluster EKS (ANTES de borrar nada)
# ==================================================================
echo -e "${AZUL}[1/9] Conectando al cluster EKS (kubeconfig)...${NC}"
CLUSTER_EXISTS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.status" --output text 2>/dev/null || echo "NOEXISTE")

if [ "$CLUSTER_EXISTS" = "ACTIVE" ]; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null
  echo -e "${VERDE}  ✅ kubeconfig configurado para: $CLUSTER_NAME${NC}"
else
  echo -e "${AMARILLO}  ⚠  El cluster $CLUSTER_NAME no existe o no está activo.${NC}"
  echo "     Se saltarán los pasos que requieren kubectl."
fi
echo ""

# ==================================================================
# 2. Borrar namespace "ep03" (Pods, Services, Deployments, HPA, ELB)
# ==================================================================
echo -e "${AZUL}[2/9] Borrando namespace $NAMESPACE desde Kubernetes...${NC}"

if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
  # Eliminar recursos dentro del namespace primero (más rápido que esperar finalizers)
  kubectl delete hpa -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true
  kubectl delete deployment -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true
  kubectl delete svc -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true
  kubectl delete pod -n "$NAMESPACE" --all --grace-period=0 --force 2>/dev/null || true

  # Eliminar el namespace
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --grace-period=0 --force 2>/dev/null || true

  # Esperar a que desaparezca (con timeout)
  echo -e "  Esperando eliminación del namespace..."
  for i in $(seq 1 30); do
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
      echo -e "${VERDE}  ✅ Namespace $NAMESPACE eliminado${NC}"
      break
    fi
    sleep 2
  done
  if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
    echo -e "${AMARILLO}  ⚠  Namespace aún existe tras 60s. Se eliminará con el stack EKS.${NC}"
  fi
else
  echo -e "${AMARILLO}  ⚠  Namespace $NAMESPACE no existe (ya fue eliminado)${NC}"
fi
echo ""

# ==================================================================
# 3. Borrar stack CloudFormation del cluster EKS
#    (esto borra: cluster EKS + NodeGroup + addons)
# ==================================================================
echo -e "${AZUL}[3/9] Borrando stack CloudFormation: $STACK_EKS...${NC}"
echo "  (Cluster EKS + NodeGroup + Addons: vpc-cni, coredns, kube-proxy, metrics-server)"
echo -e "${AMARILLO}  Tarda ~10-15 minutos...${NC}"
echo ""

STACK_EKS_EXISTS=$(aws cloudformation describe-stacks --stack-name "$STACK_EKS" --region "$REGION" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOEXISTE")

if [ "$STACK_EKS_EXISTS" != "NOEXISTE" ]; then
  aws cloudformation delete-stack \
    --stack-name "$STACK_EKS" \
    --region "$REGION"

  echo -e "  Esperando a que se borre el stack..."
  aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_EKS" \
    --region "$REGION" 2>/dev/null && \
    echo -e "${VERDE}  ✅ Stack $STACK_EKS eliminado${NC}" || \
    echo -e "${ROJO}  ❌ Error al esperar eliminación de $STACK_EKS${NC}"
else
  echo -e "${AMARILLO}  ⚠  Stack $STACK_EKS no existe${NC}"
fi
echo ""

# ==================================================================
# 4. Borrar stack CloudFormation de la VPC
#    (esto borra: VPC + subnets + Internet Gateway + VPC Endpoints)
# ==================================================================
echo -e "${AZUL}[4/9] Borrando stack CloudFormation: $STACK_VPC...${NC}"
echo "  (VPC + Subnets + Internet Gateway + VPC Endpoints)"
echo -e "${AMARILLO}  Tarda ~5 minutos...${NC}"
echo ""

STACK_VPC_EXISTS=$(aws cloudformation describe-stacks --stack-name "$STACK_VPC" --region "$REGION" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOEXISTE")

if [ "$STACK_VPC_EXISTS" != "NOEXISTE" ]; then
  aws cloudformation delete-stack \
    --stack-name "$STACK_VPC" \
    --region "$REGION"

  echo -e "  Esperando a que se borre el stack..."
  aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_VPC" \
    --region "$REGION" 2>/dev/null && \
    echo -e "${VERDE}  ✅ Stack $STACK_VPC eliminado${NC}" || \
    echo -e "${ROJO}  ❌ Error al esperar eliminación de $STACK_VPC${NC}"
else
  echo -e "${AMARILLO}  ⚠  Stack $STACK_VPC no existe${NC}"
fi
echo ""

# ==================================================================
# 5. Borrar repositorios ECR
# ==================================================================
echo -e "${AZUL}[5/9] Borrando repositorios ECR...${NC}"

for repo in ep03-db ep03-backend ep03-frontend; do
  if aws ecr describe-repositories --repository-name "$repo" --region "$REGION" &>/dev/null 2>&1; then
    aws ecr delete-repository \
      --repository-name "$repo" \
      --region "$REGION" \
      --force 2>/dev/null && \
      echo -e "  ${VERDE}$repo: ELIMINADO${NC}" || \
      echo -e "  ${ROJO}$repo: error al borrar${NC}"
  else
    echo -e "  ${AMARILLO}$repo: ya no existía${NC}"
  fi
done
echo ""

# ==================================================================
# 6. Borrar repositorios en GitHub
# ==================================================================
echo -e "${AZUL}[6/9] Borrando repositorios en GitHub...${NC}"

USER_GITHUB=$(gh api user --jq '.login' 2>/dev/null || echo "")

if [ -n "$USER_GITHUB" ]; then
  echo "  Usuario GitHub detectado: $USER_GITHUB"
  for repo in 202601_ep03_db 202601_ep03_backend 202601_ep03_frontend; do
    FULL_NAME="$USER_GITHUB/$repo"
    if gh repo view "$FULL_NAME" --json name &>/dev/null 2>&1; then
      gh repo delete "$FULL_NAME" --yes 2>/dev/null && \
        echo -e "  ${VERDE}$FULL_NAME: ELIMINADO${NC}" || \
        echo -e "  ${ROJO}$FULL_NAME: error al borrar${NC}"
    else
      echo -e "  ${AMARILLO}$FULL_NAME: ya no existía${NC}"
    fi
  done
else
  echo -e "  ${AMARILLO}⚠  No se pudo obtener usuario GitHub. Salta borrado de repos.${NC}"
fi
echo ""

# ==================================================================
# 7. Borrar directorios locales de los repos clonados
#    NOTA: Se usa la ruta relativa desde SCRIPT_DIR para ser portable
# ==================================================================
echo -e "${AZUL}[7/9] Borrando directorios locales de repositorios...${NC}"

# Ruta relativa desde bloque06/ hacia bloque04-aplicacion/paso-00-github-cli/
BASE_PASO00="$SCRIPT_DIR/../../bloque04-aplicacion/paso-00-github-cli"
BASE_PASO01="$SCRIPT_DIR/../../bloque04-aplicacion/paso-01-deploy-aws"

# Normalizar rutas
BASE_PASO00=$(cd "$BASE_PASO00" 2>/dev/null && pwd || echo "$BASE_PASO00")
BASE_PASO01=$(cd "$BASE_PASO01" 2>/dev/null && pwd || echo "$BASE_PASO01")

# Borrar directorios clonados en paso-00
if [ -d "$BASE_PASO00" ]; then
  for repo_dir in "$BASE_PASO00"/202601_ep03_*; do
    if [ -d "$repo_dir" ]; then
      rm -rf "$repo_dir"
      echo -e "  ${VERDE}Eliminado: $repo_dir${NC}"
    fi
  done
else
  echo -e "  ${AMARILLO}⚠  Directorio $BASE_PASO00 no existe${NC}"
fi

# Borrar .git de los repos en paso-01
if [ -d "$BASE_PASO01" ]; then
  for repo_dir in "$BASE_PASO01"/202601_ep03_*; do
    if [ -d "$repo_dir/.git" ]; then
      rm -rf "$repo_dir/.git"
      echo -e "  ${VERDE}.git eliminado: $repo_dir${NC}"
    fi
  done
else
  echo -e "  ${AMARILLO}⚠  Directorio $BASE_PASO01 no existe${NC}"
fi

echo -e "${VERDE}  OK${NC}"
echo ""

# ==================================================================
# 8. Limpiar CloudWatch Log Groups del cluster EKS
# ==================================================================
echo -e "${AZUL}[8/9] Limpiando CloudWatch Log Groups del cluster EKS...${NC}"

LOG_GROUPS=$(aws logs describe-log-groups \
  --region "$REGION" \
  --query "logGroups[?contains(logGroupName, '/aws/eks/$CLUSTER_NAME')].logGroupName" \
  --output text 2>/dev/null)

if [ -n "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
  for lg in $LOG_GROUPS; do
    echo "  Eliminando log group: $lg"
    aws logs delete-log-group --log-group-name "$lg" --region "$REGION" 2>/dev/null && \
      echo -e "    ${VERDE}ELIMINADO${NC}" || \
      echo -e "    ${AMARILLO}error (puede necesitar permisos adicionales)${NC}"
  done
else
  echo -e "  ${AMARILLO}No se encontraron log groups para $CLUSTER_NAME${NC}"
fi
echo ""

# ==================================================================
# 9. Limpiar kubeconfig local + known_hosts
# ==================================================================
echo -e "${AZUL}[9/9] Limpiando kubeconfig local y known_hosts...${NC}"

# Obtener el ARN del cluster para los nombres de contexto
CLUSTER_ARN="arn:aws:eks:$REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME"

# Eliminar contexto, cluster y usuario del kubeconfig
kubectl config delete-context "$CLUSTER_ARN" 2>/dev/null || true
kubectl config delete-cluster "$CLUSTER_ARN" 2>/dev/null || true
kubectl config delete-user "$CLUSTER_ARN" 2>/dev/null || true

# También limpiar contextos alternativos que pueda haber generado update-kubeconfig
kubectl config unset "contexts.$CLUSTER_NAME" 2>/dev/null || true
kubectl config unset "clusters.$CLUSTER_NAME" 2>/dev/null || true

echo -e "  ${VERDE}kubeconfig limpiado${NC}"

# Limpiar known_hosts de github.com
ssh-keygen -R github.com 2>/dev/null || true
echo -e "  ${VERDE}known_hosts de github.com limpiado${NC}"

echo ""

# ==================================================================
# VERIFICACIÓN FINAL
# ==================================================================
echo -e "${AZUL}=============================================================${NC}"
echo -e "${AZUL} VERIFICANDO LIMPIEZA...${NC}"
echo -e "${AZUL}=============================================================${NC}"
echo ""

ERRORES=0

# Verificar namespace
if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
  echo -e "  ${ROJO}❌ Namespace $NAMESPACE aún existe${NC}"
  ERRORES=$((ERRORES + 1))
else
  echo -e "  ${VERDE}✅ Namespace $NAMESPACE: eliminado${NC}"
fi

# Verificar stacks CF
for stack in "$STACK_EKS" "$STACK_VPC"; do
  STATUS=$(aws cloudformation describe-stacks --stack-name "$stack" --region "$REGION" --query "Stacks[0].StackStatus" --output text 2>/dev/null)
  if [ -n "$STATUS" ] && [ "$STATUS" != "NOEXISTE" ]; then
    echo -e "  ${ROJO}❌ Stack $stack: $STATUS${NC}"
    ERRORES=$((ERRORES + 1))
  else
    echo -e "  ${VERDE}✅ Stack $stack: eliminado${NC}"
  fi
done

# Verificar ECR repos
for repo in ep03-db ep03-backend ep03-frontend; do
  if aws ecr describe-repositories --repository-name "$repo" --region "$REGION" &>/dev/null 2>&1; then
    echo -e "  ${ROJO}❌ ECR $repo: aún existe${NC}"
    ERRORES=$((ERRORES + 1))
  else
    echo -e "  ${VERDE}✅ ECR $repo: eliminado${NC}"
  fi
done

# Verificar GitHub repos
if [ -n "$USER_GITHUB" ]; then
  for repo in 202601_ep03_db 202601_ep03_backend 202601_ep03_frontend; do
    FULL_NAME="$USER_GITHUB/$repo"
    if gh repo view "$FULL_NAME" --json name &>/dev/null 2>&1; then
      echo -e "  ${ROJO}❌ GitHub $FULL_NAME: aún existe${NC}"
      ERRORES=$((ERRORES + 1))
    else
      echo -e "  ${VERDE}✅ GitHub $FULL_NAME: eliminado${NC}"
    fi
  done
fi

echo ""

# ==================================================================
# FIN
# ==================================================================
echo -e "${AZUL}=============================================================${NC}"
if [ "$ERRORES" -eq 0 ]; then
  echo -e "${VERDE} ETAPA 12 COMPLETADA — Laboratorio limpio para empezar desde 0${NC}"
else
  echo -e "${AMARILLO} ETAPA 12 COMPLETADA CON $ERRORES ERROR(ES) — Revisa mensajes arriba${NC}"
fi
echo -e "${AZUL}=============================================================${NC}"
echo ""
echo "  Borrado:"
echo "    [X] Namespace $NAMESPACE (Pods, Services, ELB, HPA)"
echo "    [X] Stack $STACK_EKS (EKS + NodeGroup + Addons)"
echo "    [X] Stack $STACK_VPC (VPC + Subnets + Endpoints)"
echo "    [X] Repositorios ECR (ep03-db, ep03-backend, ep03-frontend)"
echo "    [X] Repositorios en GitHub (202601_ep03_*)"
echo "    [X] Directorios locales de repos clonados"
echo "    [X] CloudWatch Log Groups del cluster"
echo "    [X] kubeconfig limpiado"
echo "    [X] known_hosts de github.com limpiado"
echo ""
echo -e "  ${VERDE}Ya puedes rehacer el laboratorio desde: cd ../etapa01-ValidaEntorno${NC}"
echo ""
