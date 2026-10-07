#!/bin/bash
set -e

# =====================================================
# Script: crear_repos.sh
# Crea en GitHub los 3 repositorios de la aplicación a
# partir de las carpetas locales y los sube (push).
#
# Lee GITHUB_TOKEN desde ../secrets.txt.
#
# Carpetas locales -> repositorios en GitHub:
#   ep02_ing_devops_database
#   ep02_ing_devops_backend
#   ep02_ing_devops_frontend
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="../secrets.txt"

# Orden de despliegue: database, backend, frontend
REPO_DIRS=(
  "ep02_ing_devops_database"
  "ep02_ing_devops_backend"
  "ep02_ing_devops_frontend"
)

banner() {
  echo ""
  echo "========================================="
  echo " $1"
  echo "========================================="
  echo ""
}

# Lee el valor de una clave desde secrets.txt (case-insensitive)
obtener_valor() {
  local target="$1"
  local file="$2"
  awk -F'=' -v key="$target" '
    /^[[:space:]]*#/ { next }
    {
      k = $1
      gsub(/[[:space:]]/, "", k)
      if (toupper(k) == toupper(key)) {
        sub(/^[^=]*=/, "")
        v = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

banner "CREACIÓN DE REPOSITORIOS EN GITHUB"

# Verificar GitHub CLI
if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) no está instalado."
  echo "       Instálalo con: brew install gh"
  exit 1
fi

# Verificar secrets.txt
if [ ! -f "$SECRETS_FILE" ]; then
  echo "ERROR: No se encontró $SECRETS_FILE"
  exit 1
fi

# Obtener GITHUB_TOKEN
GITHUB_TOKEN="$(obtener_valor "GITHUB_TOKEN" "$SECRETS_FILE")"
if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN no está definido en $SECRETS_FILE"
  exit 1
fi
echo "Token leído desde: $SECRETS_FILE"

# Autenticar con GitHub CLI usando el token de secrets.txt
# gh detecta GH_TOKEN automáticamente; no se requiere "gh auth login".
export GH_TOKEN="$GITHUB_TOKEN"
echo "Usando GITHUB_TOKEN para autenticar..."

GH_OWNER="$(gh api user -q '.login')"
echo "Usuario GitHub: $GH_OWNER"

# Crear y subir cada repositorio
for name in "${REPO_DIRS[@]}"; do
  dir="${SCRIPT_DIR}/${name}"
  banner "Repositorio: $name"

  if [ ! -d "$dir" ]; then
    echo "ADVERTENCIA: No existe la carpeta $dir (omitido)"
    continue
  fi

  (
    cd "$dir"

    if [ ! -d .git ]; then
      echo "Inicializando repositorio git..."
      git init -b main > /dev/null 2>&1 || git init > /dev/null
    fi

    # Identidad git local de respaldo (útil en contenedores sin config global)
    if ! git config user.email > /dev/null 2>&1; then
      git config user.email "${GH_OWNER}@users.noreply.github.com"
      git config user.name "${GH_OWNER}"
    fi

    git add -A

    if git diff --cached --quiet; then
      echo "Sin cambios para commitear"
    else
      git commit -q -m "Initial commit: $name"
      echo "Commit inicial creado"
    fi

    if gh repo view "$GH_OWNER/$name" > /dev/null 2>&1; then
      echo "El repositorio ya existe en GitHub. Configurando remoto y push..."
      git remote get-url origin > /dev/null 2>&1 || \
        git remote add origin "https://github.com/$GH_OWNER/$name.git"
      git push -u origin HEAD
    else
      echo "Creando repositorio $GH_OWNER/$name..."
      gh repo create "$GH_OWNER/$name" \
        --public \
        --source=. \
        --remote=origin \
        --push
    fi
  )

  echo "  ✔ https://github.com/$GH_OWNER/$name"
done

banner "RESUMEN"
for name in "${REPO_DIRS[@]}"; do
  echo "  ✔ https://github.com/$GH_OWNER/$name"
done
echo ""
echo "PROCESO COMPLETADO"
