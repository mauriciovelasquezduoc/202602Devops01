#!/bin/bash
set -euo pipefail

# =====================================================
# Script: url-app.sh
# Obtiene y muestra la URL pública de la aplicación
# (Service LoadBalancer del frontend en el namespace ep02),
# y verifica que la app realmente responda.
#
# Uso:
#   ./url-app.sh              # muestra la URL (espera a que el ELB exista)
#   ./url-app.sh --open       # además la abre en el navegador
#   ./url-app.sh --salud      # reporte de salud de toda la plataforma
#   ./url-app.sh --salud      # también corre si algo falla en el flujo normal
#
# Lee credenciales de secrets.txt.
# Variables opcionales:
#   NAMESPACE=ep02 SERVICE=ep02-frontend REGION=us-east-1 \
#   CLUSTER_NAME=laboratorio-ep02-eks ./url-app.sh
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.txt"
# Fallback: si no está junto al script, probar en el directorio actual
if [ ! -f "$SECRETS_FILE" ] && [ -f "./secrets.txt" ]; then
  SECRETS_FILE="./secrets.txt"
fi

# Cargar credenciales de secrets.txt (para que aws/kubectl autentiquen)
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

NAMESPACE="${NAMESPACE:-ep02}"
SERVICE="${SERVICE:-ep02-frontend}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"
CLUSTER_NAME="${CLUSTER_NAME:-laboratorio-ep02-eks}"
NODEGROUP_NAME="${NODEGROUP_NAME:-laboratorio-ep02-nodegroup}"
ECR_REPOS=("ep02-database" "ep02-backend" "ep02-frontend")

OPEN=false
SALUD=false
for arg in "$@"; do
  case "$arg" in
    --open|-o) OPEN=true ;;
    --salud|-s) SALUD=true ;;
    -h|--help)
      echo "Uso: ./url-app.sh [--open] [--salud]"
      echo "  --open   abre la URL en el navegador"
      echo "  --salud  solo genera el reporte de salud de la plataforma"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg"
      echo "Uso: ./url-app.sh [--open] [--salud]"
      exit 1
      ;;
  esac
done

banner() {
  echo ""
  echo "========================================="
  echo " $1"
  echo "========================================="
  echo ""
}

VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; AZUL='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${VERDE}  ✔ $*${NC}"; }
warn() { echo -e "${AMAR}  ⚠ $*${NC}"; }
fail() { echo -e "${ROJO}  ✘ $*${NC}"; }
info() { echo -e "${AZUL}  ℹ $*${NC}"; }

# -----------------------------------------------------------------
# Recuperación de credenciales:
# 1) Valida la conexión con aws sts get-caller-identity.
# 2) Si falla, configura las credenciales con aws configure set
#    leyendo secrets.txt y vuelve a validar.
# 3) Refresca el kubeconfig del cluster EKS.
# -----------------------------------------------------------------
recover_aws() {
  echo ""
  echo "Validando conexión con AWS (aws sts get-caller-identity)..."
  if aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
    ok "credenciales AWS válidas."
    return 0
  fi

  echo "Sin conexión válida a AWS. Configurando credenciales desde secrets.txt..."
  if [ ! -f "$SECRETS_FILE" ]; then
    fail "no encontré secrets.txt (busqué en $SCRIPT_DIR y en el directorio actual)."
    return 1
  fi

  local akid="" sk="" tok=""
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="${key//[[:space:]]/}"
    case "$key" in
      aws_access_key_id)     akid="$value" ;;
      aws_secret_access_key) sk="$value" ;;
      aws_session_token)     tok="$value" ;;
    esac
  done < "$SECRETS_FILE"

  if [ -z "$akid" ] || [ -z "$sk" ]; then
    fail "secrets.txt no contiene aws_access_key_id / aws_secret_access_key."
    return 1
  fi

  aws configure set aws_access_key_id     "$akid"      --region "$REGION"
  aws configure set aws_secret_access_key "$sk"
  if [ -n "$tok" ]; then
    aws configure set aws_session_token   "$tok"
  else
    aws configure set aws_session_token   "" 2>/dev/null || true
  fi
  aws configure set region                "$REGION"

  export AWS_ACCESS_KEY_ID="$akid"
  export AWS_SECRET_ACCESS_KEY="$sk"
  if [ -n "$tok" ]; then
    export AWS_SESSION_TOKEN="$tok"
  else
    unset AWS_SESSION_TOKEN || true
  fi

  if aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
    ok "credenciales configuradas y validadas."
  else
    fail "las credenciales de secrets.txt no son válidas (token de sesión expirado)."
    return 1
  fi

  echo "Actualizando kubeconfig: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" > /dev/null 2>&1 \
    || warn "no pude actualizar el kubeconfig (¿existe el cluster $CLUSTER_NAME?)."
}

# -----------------------------------------------------------------
# Reporte de salud de la plataforma (todas las capas)
# Imprime un diagnostico por capa + causas probables + acciones.
# -----------------------------------------------------------------
reporte_salud() {
  local problemas=0

  banner "REPORTE DE SALUD DE LA PLATAFORMA"
  echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S') · Región: $REGION · Cluster: $CLUSTER_NAME"
  echo ""

  # ---- Capa 0: herramientas ----
  echo "--- [0] Herramientas ---"
  for cmd in aws kubectl curl; do
    if command -v "$cmd" > /dev/null 2>&1; then ok "$cmd instalado"; else fail "$cmd NO instalado"; problemas=$((problemas+1)); fi
  done
  echo ""

  # ---- Capa 1: credenciales AWS ----
  echo "--- [1] Credenciales AWS (sts get-caller-identity) ---"
  if AWS_STATUS_ARN="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" && [ -n "${AWS_STATUS_ARN:-}" ]; then
    ok "sesión válida: $AWS_STATUS_ARN"
    AWS_SESSION_ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
  else
    fail "credenciales inválidas o EXPIRADAS (token de sesión temporal de Academy)"
    info "acción: AWS Academy > AWS Details > AWS CLI > copiar y actualizar secrets.txt"
    problemas=$((problemas+1))
  fi
  echo ""

  # ---- Capa 2: cluster EKS ----
  echo "--- [2] Cluster EKS ($CLUSTER_NAME) ---"
  EKS_STATUS="$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NO_EXISTE")"
  case "$EKS_STATUS" in
    ACTIVE)
      ok "cluster $CLUSTER_NAME: ACTIVE"
      echo "  Refrescando kubeconfig..."
      if aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" > /dev/null 2>&1; then
        ok "kubeconfig actualizado"
      else
        warn "no se pudo actualizar el kubeconfig"
        problemas=$((problemas+1))
      fi
      ;;
    NO_EXISTE)
      fail "el cluster NO existe (la sesión del lab se cerró o se hizo aws-limpiar.sh)"
      info "acción: reconstruir infraestructura:  cd bloque01-infra-k8s && bash ejecutar.sh"
      info "acción: luego re-desplegar:          cd bloque03-k8s && ./apply-all.sh"
      info "acción: y subir imágenes si faltan:  bash push-imagenes.sh (desde la Mac)"
      problemas=$((problemas+1))
      ;;
    *)
      warn "cluster en estado $EKS_STATUS (espera o revisa CloudFormation)"
      problemas=$((problemas+1))
      ;;
  esac
  echo ""

  # Si no hay cluster ni credenciales, no tiene sentido seguir con k8s
  if [ "$EKS_STATUS" != "ACTIVE" ]; then
    echo "========================================="
    echo " ESTADO GENERAL: CAÍDO ($problemas problema(s))"
    echo "========================================="
    info "Sin cluster activo no hay app. Revisa las acciones [1] y [2]."
    return $problemas
  fi

  # ---- Capa 3: nodegroup y nodos ----
  echo "--- [3] Nodos (NodeGroup $NODEGROUP_NAME) ---"
  NG_STATUS="$(aws eks describe-nodegroup --region "$REGION" --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODEGROUP_NAME" --query 'nodegroup.status' --output text 2>/dev/null || echo "NO_EXISTE")"
  case "$NG_STATUS" in
    ACTIVE) ok "nodegroup: ACTIVE" ;;
    NO_EXISTE)
      fail "nodegroup NO existe"
      info "acción: reconstruir infraestructura:  cd bloque01-infra-k8s && bash ejecutar.sh"
      problemas=$((problemas+1))
      ;;
    *) warn "nodegroup en estado $NG_STATUS"; problemas=$((problemas+1)) ;;
  esac

  if kubectl get nodes > /dev/null 2>&1; then
    TOTAL_NODES="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    READY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)"
    if [ "${READY_NODES:-0}" -gt 0 ]; then
      ok "nodos Ready: $READY_NODES de $TOTAL_NODES"
      kubectl get nodes 2>/dev/null | awk 'NR>1 {print "    ", $1, $2}'
    else
      fail "ningún nodo Ready ($TOTAL_NODES registrados)"
      info "causa típica tras apagar el lab: el nodo SPOT no se repuso"
      info "acción: forzar el ciclo del nodegroup (0 -> 1):"
      info "  aws eks update-nodegroup-config --region $REGION --cluster-name $CLUSTER_NAME \\"
      info "    --nodegroup-name $NODEGROUP_NAME --scaling-config minSize=0,maxSize=3,desiredSize=0"
      info "  # (espera ~1 min, luego)"
      info "  aws eks update-nodegroup-config --region $REGION --cluster-name $CLUSTER_NAME \\"
      info "    --nodegroup-name $NODEGROUP_NAME --scaling-config minSize=1,maxSize=3,desiredSize=1"
      problemas=$((problemas+1))
    fi
  else
    fail "kubectl no puede hablar con el cluster (kubeconfig o red)"
    problemas=$((problemas+1))
  fi
  echo ""

  # ---- Capa 4: pods del namespace ----
  echo "--- [4] Pods del namespace $NAMESPACE ---"
  if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    ok "namespace $NAMESPACE accesible"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null | awk 'NR>1 {print "    ", $0}'
    NO_READY="$(kubectl get pods -n "$NAMESPACE" 2>/dev/null | awk 'NR>1 && $2 !~ /^[0-9]+\/[0-9]+$/ {print $1" "$3}' || true)"
    MALOS="$(kubectl get pods -n "$NAMESPACE" 2>/dev/null | awk 'NR>1 && $3 != "Running" && $3 != "Completed" {print $1" ("$3")"}' || true)"
    if [ -n "$MALOS" ]; then
      fail "pods con problemas:"
      echo "$MALOS" | while read -r p; do echo "      - $p"; done
      case "$MALOS" in
        *ImagePullBackOff*|*ErrImagePull*)
          info "causa: la imagen no existe en ECR (¿el lab se cerró y ECR se vació?)"
          info "acción: subir imágenes:  bash push-imagenes.sh  (desde tu Mac)"
          ;;
        *CrashLoopBackOff*)
          info "causa: la app crashea al arrancar — ver logs:"
          info "acción: kubectl logs POD -n $NAMESPACE --previous"
          ;;
        *Pending*)
          info "causa: no hay recursos/nodos disponibles"
          ;;
      esac
      problemas=$((problemas+1))
    elif [ -n "$NO_READY" ]; then
      warn "pods arrancando (no Ready aún): $NO_READY"
    else
      ok "todos los pods Running y Ready"
    fi
  else
    fail "namespace $NAMESPACE NO accesible (¿bloque03 aplicado en este cluster?)"
    info "acción: desplegar la app:  cd bloque03-k8s && ./apply-all.sh"
    problemas=$((problemas+1))
  fi
  echo ""

  # ---- Capa 5: imágenes en ECR ----
  echo "--- [5] Imágenes en ECR ---"
  for repo in "${ECR_REPOS[@]}"; do
    TAGS="$(aws ecr describe-images --repository-name "$repo" --region "$REGION" \
      --query 'imageDetails[].imageTags[]' --output text 2>/dev/null | tr '\t' ' ' || true)"
    if [ -n "${TAGS// /}" ]; then
      if echo "$TAGS" | grep -q "latest"; then
        ok "$repo: tags [$TAGS]"
      else
        warn "$repo: imágenes sin tag latest [$TAGS]"
        problemas=$((problemas+1))
      fi
    else
      fail "$repo: VACÍO (sin imágenes)"
      info "acción: bash push-imagenes.sh (desde tu Mac)"
      problemas=$((problemas+1))
    fi
  done
  echo ""

  # ---- Capa 6: Service y LoadBalancer ----
  echo "--- [6] Service $SERVICE y LoadBalancer ---"
  HOST="$(kubectl get svc "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$HOST" ]; then
    ok "URL del ELB: http://$HOST"
  else
    fail "el Service no tiene hostname externo (ELB sin aprovisionar)"
    info "acción: espera 2-3 min y reintenta; revisa: kubectl describe svc $SERVICE -n $NAMESPACE"
    problemas=$((problemas+1))
  fi

  ENDPOINTS="$(kubectl get endpoints "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -n "${ENDPOINTS// /}" ]; then
    ok "endpoints con IPs: $ENDPOINTS"
  else
    fail "endpoints VACÍOS: el ELB no tiene pods detrás (aquí nace el ERR_EMPTY_RESPONSE)"
    info "causa típica: pods no Ready (capa 4) o selector del Service mal apuntado"
    problemas=$((problemas+1))
  fi
  echo ""

  # ---- Capa 7: prueba HTTP real contra el ELB ----
  echo "--- [7] Prueba HTTP (desde aquí, contra el ELB) ---"
  if [ -n "${HOST:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$HOST/" || true)"
      case "$HTTP_CODE" in
        200) ok "HTTP $HTTP_CODE — la app responde 🎉" ;;
        503)
          fail "HTTP $HTTP_CODE — el ELB responde pero no tiene backends saludables"
          info "coincide con endpoints vacíos o pods no Ready (capas 4 y 6)"
          problemas=$((problemas+1))
          ;;
        ""|000)
          fail "sin respuesta HTTP (timeout/reset) — revisa Security Groups o prueba desde tu Mac"
          info "el ELB puede existir pero no estar accesible desde el contenedor"
          problemas=$((problemas+1))
          ;;
        *)
          warn "HTTP $HTTP_CODE — respuesta inesperada, revisa logs del frontend"
          problemas=$((problemas+1))
          ;;
      esac
    else
      warn "curl no disponible; prueba manual: curl -v http://$HOST/"
    fi
  else
    fail "no hay hostname: no se puede probar HTTP"
    problemas=$((problemas+1))
  fi
  echo ""

  # ---- Resumen ----
  echo "========================================="
  if [ "$problemas" -eq 0 ]; then
    echo " ESTADO GENERAL: ✅ SALUDABLE"
    [ -n "${HOST:-}" ] && echo " URL: http://$HOST"
  elif [ "$problemas" -le 2 ]; then
    echo " ESTADO GENERAL: ⚠ DEGRADADO ($problemas problema(s))"
  else
    echo " ESTADO GENERAL: ✘ CAÍDO ($problemas problema(s))"
  fi
  echo "========================================="
  echo ""
  info "Secuencia completa de arranque tras cerrar el lab:"
  info "  1. cd bloque01-infra-k8s && bash ejecutar.sh   (si el cluster no existe)"
  info "  2. bash push-imagenes.sh                       (si ECR está vacío, desde la Mac)"
  info "  3. cd bloque03-k8s && ./apply-all.sh           (si la app no está desplegada)"
  info "  4. bash url-app.sh                             (esta URL + verificación)"

  return $problemas
}

banner "URL DE LA APLICACIÓN"

if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl no está instalado."
  exit 1
fi
if ! command -v aws &> /dev/null; then
  echo "ERROR: aws CLI no está instalado."
  exit 1
fi

# Modo reporte de salud puro
if [ "$SALUD" = true ]; then
  reporte_salud
  exit $?
fi

# Verificar acceso al cluster (con intento de recuperación automática)
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo "No puedo acceder al namespace $NAMESPACE. Intentando recuperar credenciales..."
  recover_aws || true
  if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo ""
    warn "no puedo acceder al namespace $NAMESPACE — genero el reporte de salud para diagnosticar:"
    reporte_salud || true
    exit 1
  fi
fi
ok "acceso al namespace $NAMESPACE confirmado."

# -----------------------------------------------------------------
# Detalle de pods por deployment (database, backend, frontend)
# -----------------------------------------------------------------
detalle_pods() {
  echo ""
  echo "--- Detalle de pods ---"
  local total_malos=0
  for app_label in "${NAMESPACE}-database" "${NAMESPACE}-backend" "${NAMESPACE}-frontend"; do
    if ! kubectl get deployment "$app_label" -n "$NAMESPACE" > /dev/null 2>&1; then
      fail "$app_label: el deployment NO existe (¿apply-all.sh ejecutado?)"
      total_malos=$((total_malos+1))
      continue
    fi

    local deseados_listos estado pods detalle
    deseados="$(kubectl get deployment "$app_label" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")"
    listos="$(kubectl get deployment "$app_label" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    pods="$(kubectl get pods -n "$NAMESPACE" -l "app=$app_label" -o wide --no-headers 2>/dev/null || true)"

    if [ "${listos:-0}" -eq "${deseados:-0}" ] && [ -n "${pods// /}" ] && ! echo "$pods" | awk '{exit ($3=="Running" && $2 ~ /^[0-9]+\/[0-9]+$/) ? 1 : 0}'; then
      ok "$app_label: $listos/$deseados Ready — todo OK"
      echo "$pods" | awk '{printf "      %s  READY=%s  %s  restarts=%s  node=%s\n", $1, $2, $3, $4, $7}'
    else
      fail "$app_label: $listos/$deseados Ready — NO OK"
      echo "$pods" | awk '{printf "      %s  READY=%s  %s  restarts=%s  node=%s\n", $1, $2, $3, $4, $7}'
      total_malos=$((total_malos+1))
      # Diagnóstico del primer pod con problemas
      MAL_POD="$(echo "$pods" | awk '$3!="Running" || $2 !~ /^[0-9]+\/[0-9]+$/ {print $1; exit}' || true)"
      MAL_ESTADO="$(echo "$pods" | awk '$3!="Running" || $2 !~ /^[0-9]+\/[0-9]+$/ {print $3; exit}' || true)"
      if [ -n "${MAL_POD:-}" ]; then
        case "$MAL_ESTADO" in
          Pending|ImagePullBackOff|ErrImagePull)
            info "$MAL_POD ($MAL_ESTADO) → imagen ECR o recursos:"
            info "  kubectl describe pod $MAL_POD -n $NAMESPACE | tail -20"
            info "  aws ecr describe-images --repository-name $app_label --region $REGION --query 'imageDetails[].imageTags[]' --output text"
            ;;
          CrashLoopBackOff|Error)
            info "$MAL_POD ($MAL_ESTADO) → la app crashea:"
            info "  kubectl logs $MAL_POD -n $NAMESPACE --previous | tail -30"
            ;;
          *)
            info "$MAL_POD ($MAL_ESTADO) → revisa eventos:"
            info "  kubectl describe pod $MAL_POD -n $NAMESPACE"
            ;;
        esac
      fi
    fi
    echo ""
  done

  if [ "$total_malos" -gt 0 ]; then
    echo "$total_malos deployment(s) con problemas — la URL puede responder vacío (ERR_EMPTY_RESPONSE) hasta que estén Ready."
  else
    echo "Todos los deployments OK — continuando con la URL..."
  fi
}

detalle_pods

# Esperar a que el Service LoadBalancer tenga hostname externo
echo "Esperando el hostname del Service $SERVICE (namespace $NAMESPACE)..."
HOST=""
for i in $(seq 1 60); do
  HOST="$(kubectl get svc "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$HOST" ]; then
    break
  fi
  echo "  ... aún sin hostname ($i/60)"
  sleep 10
done

echo ""
echo "--- Service $SERVICE ---"
kubectl get svc "$SERVICE" -n "$NAMESPACE" -o wide 2>/dev/null || true
echo ""

if [ -z "$HOST" ]; then
  echo "ADVERTENCIA: el Service $SERVICE no tiene hostname externo todavía."
  echo "  - ¿El frontend está desplegado?  kubectl get pods -n $NAMESPACE"
  echo "  - ¿El ELB está aprovisionando?   vuelve a intentar en 1-2 minutos."
  warn "genero el reporte de salud para diagnosticar:"
  reporte_salud || true
  exit 1
fi

# Verificar que el ELB realmente responda (el ERR_EMPTY_RESPONSE se detecta aquí)
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$HOST/" 2>/dev/null || true)"
echo ""
echo "--- Verificación HTTP ---"
if [ "$HTTP_CODE" = "200" ]; then
  ok "la app responde (HTTP $HTTP_CODE)"
elif [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
  warn "el ELB no devolvió respuesta HTTP (¿ERR_EMPTY_RESPONSE en el navegador?)"
  info "genero el reporte de salud para diagnosticar:"
  reporte_salud || true
  exit 1
else
  warn "el ELB respondió HTTP $HTTP_CODE (no 200)"
  info "genero el reporte de salud para diagnosticar:"
  reporte_salud || true
  exit 1
fi

URL="http://$HOST"
banner "URL: $URL"
if [ "$OPEN" = true ]; then
  if command -v open &> /dev/null; then
    open "$URL"
  elif command -v xdg-open &> /dev/null; then
    xdg-open "$URL"
  else
    echo "(no pude abrir el navegador automáticamente)"
  fi
fi
