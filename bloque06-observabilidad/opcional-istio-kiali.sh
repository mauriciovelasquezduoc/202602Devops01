#!/usr/bin/env bash
# ==================================================================
# BLOQUE 06 - OPCIONAL: SERVICE MESH con ISTIO + KIALI
#
# ⚠  RECURSOS: Istio añade ~1.5-2 GB de RAM y CPU al nodo t3.large.
#    En AWS Academy (1 nodo SPOT) puede quedar apretado. Es la última
#    actividad de la semana: si el nodo no aguanta, la teoría del
#    README y las demos 1-3 ya cubren los objetivos de aprendizaje.
#
# ¿QUE HACE? (idempotente y con soporte de limpieza: LIMPIAR=1)
#   1. Instala istioctl y el perfil "demo" (istiod + ingressgateway)
#   2. Inyecta el sidecar Envoy en los pods del namespace ep02
#   3. Instala Prometheus + Kiali (visualización del tráfico)
#   4. Crea Gateway + VirtualService para exponer la app por la malla
#   5. Con LIMPIAR=1 bash opcional-istio-kiali.sh  ->  desinstala todo
#
# ¿TERMINOS QUE DEBES RECONOCER (Semana 14)?
#   - Pod          : la unidad mínima que corre tu contenedor
#   - Service      : la "IP estable" que reparte tráfico entre pods
#   - VirtualService: REGLA de la malla: a dónde va el tráfico, con
#                    qué ruta/peso/reintentos
#   - Gateway      : la "puerta de entrada" de la malla hacia Internet
#   - Service mesh : capa que intercepta TODO el tráfico entre pods
#                    (sidecar Envoy) para dar tráfico controlado,
#                    seguridad mTLS y observabilidad, SIN tocar el código.
# ==================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ep02"
ISTIO_NS="istio-system"
# Sin versión fija se usa la última estable (compatibilidad con el k8s 1.32 del
# cluster). Se puede fijar con: ISTIO_VERSION=1.26.2 bash opcional-istio-kiali.sh
ISTIO_VERSION="${ISTIO_VERSION:-}"

AZUL='\033[0;34m'; VERDE='\033[0;32m'; AMAR='\033[0;33m'; ROJO='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${AZUL}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()    { echo -e "${VERDE}  ✔ $*${NC}"; }
warn()  { echo -e "${AMAR}  ⚠ $*${NC}"; }
fail()  { echo -e "${ROJO}  ✘ $*${NC}"; exit 1; }
paso()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ------------------------------------------------------------------
if [ "${LIMPIAR:-0}" = "1" ]; then
  paso "LIMPIEZA — desinstalando Istio + Kiali"
  log "Eliminando recursos de la malla en ep02 e istio-system..."
  kubectl delete gateway,virtualservice --all -n "$NAMESPACE" >/dev/null 2>&1 || true
  kubectl label ns "$NAMESPACE" istio-injection- >/dev/null 2>&1 || true
  kubectl delete ns "$ISTIO_NS" --ignore-not-found >/dev/null 2>&1 || true
  log "Los pods del namespace seguirán teniendo sidecar hasta que se recreen:"
  kubectl -n "$NAMESPACE" rollout restart deploy || true
  ok "Istio/Kiali desinstalados."
  exit 0
fi

# ------------------------------------------------------------------
paso "1/5 — Descargar istioctl"
# ------------------------------------------------------------------
if [ -z "$ISTIO_VERSION" ]; then
  ISTIO_VERSION="$(curl -s https://api.github.com/repos/istio/istio/releases/latest | jq -r .tag_name | tr -d 'v')"
  case "$ISTIO_VERSION" in ""|"null") ISTIO_VERSION="1.26.2";; esac
fi
log "Versión de Istio a instalar: $ISTIO_VERSION"
if ! command -v istioctl >/dev/null 2>&1; then
  curl -sL "https://istio.io/downloadIstio" | ISTIO_VERSION="$ISTIO_VERSION" sh - >/dev/null
  sudo install "istio-$ISTIO_VERSION/bin/istioctl" /usr/local/bin/ 2>/dev/null \
    || install "istio-$ISTIO_VERSION/bin/istioctl" /usr/local/bin/
  rm -rf "istio-$ISTIO_VERSION"
fi
ok "istioctl $(istioctl version --remote=false 2>/dev/null || echo instalado)"

# ------------------------------------------------------------------
paso "2/5 — Instalar la malla (perfil demo: istiod + ingressgateway)"
# ------------------------------------------------------------------
if kubectl get ns "$ISTIO_NS" >/dev/null 2>&1; then
  ok "Istio ya está instalado."
else
  istioctl install --set profile=demo -y
  kubectl rollout status deploy/istiod -n "$ISTIO_NS" --timeout=300s
fi
ok "istiod operativo."

# ------------------------------------------------------------------
paso "3/5 — Inyectar el sidecar Envoy en ep02"
# ------------------------------------------------------------------
# El sidecar es un contenedor EXTRA dentro de cada pod que intercepta
# todo el tráfico entrante/saliente: ahí vive la malla.
kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}' | grep -q enabled \
  || kubectl label ns "$NAMESPACE" istio-injection=enabled
ok "Namespace ep02 etiquetado para inyección automática"

echo -e "${AMAR}Se reiniciarán los deployments para que nazcan CON sidecar (breve interrupción).${NC}"
read -r -p "▶ ENTER para reiniciar los deployments..."
kubectl -n "$NAMESPACE" rollout restart deploy
kubectl -n "$NAMESPACE" rollout status deploy/ep02-frontend --timeout=300s
kubectl -n "$NAMESPACE" rollout status deploy/ep02-backend  --timeout=300s
kubectl get pods -n "$NAMESPACE"
echo -e "Fíjate: cada pod ahora tiene 2/2 o 3/3 contenedores — app + sidecar Envoy."

# ------------------------------------------------------------------
paso "4/5 — Prometheus + Kiali (ver el tráfico)"
# ------------------------------------------------------------------
if ! kubectl get svc prometheus -n "$ISTIO_NS" >/dev/null 2>&1; then
  kubectl apply -f "https://raw.githubusercontent.com/istio/istio/$ISTIO_VERSION/samples/addons/prometheus.yaml"
  kubectl rollout status deploy/prometheus -n "$ISTIO_NS" --timeout=300s
fi
ok "Prometheus operativo (Kiali lo usa como fuente de datos)"
if ! kubectl get svc kiali -n "$ISTIO_NS" >/dev/null 2>&1; then
  kubectl apply -f "https://raw.githubusercontent.com/istio/istio/$ISTIO_VERSION/samples/addons/kiali.yaml"
  kubectl rollout status deploy/kiali -n "$ISTIO_NS" --timeout=300s
fi
ok "Kiali operativo"

# ------------------------------------------------------------------
paso "5/5 — Gateway + VirtualService (la app expuesta POR la malla)"
# ------------------------------------------------------------------
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: ep02-gateway
  namespace: $NAMESPACE
spec:
  selector:
    istio: ingressgateway
  servers:
  - port: { number: 80, name: http, protocol: HTTP }
    hosts: ["*"]
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ep02-vs
  namespace: $NAMESPACE
spec:
  hosts: ["*"]
  gateways: [ep02-gateway]
  http:
  - route:
    - destination: { host: ep02-frontend, port: { number: 80 } }
EOF
ok "Gateway ep02-gateway + VirtualService ep02-vs creados"

INGRESS_HOST="$(kubectl get svc istio-ingressgateway -n "$ISTIO_NS" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pendiente')"
ok "App expuesta por la malla en: http://$INGRESS_HOST/"

echo ""
echo -e "${VERDE}════════════════════════════════════════════════════════${NC}"
echo -e "${VERDE} ISTIO + KIALI LISTOS${NC}"
echo -e "${VERDE}════════════════════════════════════════════════════════${NC}"
echo -e "1) Genera tráfico:  bash demo-2-prueba-carga.sh"
echo -e "2) Abre Kiali (UI): primero levanta el contenedor con  -p 20001:20001"
echo -e "   kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo -e "   y abre http://localhost:20001  (acceso directo: el addon usa autenticación anonymous)"
echo -e "3) En Kiali: Traffic Graph → namespace ep02 → observa tráfico, errores y conexiones."
echo -e ""
echo -e "Limpieza cuando termines:  LIMPIAR=1 bash $0"
