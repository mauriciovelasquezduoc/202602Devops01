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

  # Si el repositorio ya existe en GitHub, no se hace nada.
  if gh repo view "$GH_OWNER/$name" > /dev/null 2>&1; then
    echo "El repositorio $GH_OWNER/$name ya existe. Omitido (no se modifica)."
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

    echo "Creando repositorio $GH_OWNER/$name..."
    gh repo create "$GH_OWNER/$name" \
      --public \
      --source=. \
      --remote=origin \
      --push
  )

  echo "  ✔ https://github.com/$GH_OWNER/$name"
done

banner "RESUMEN"
for name in "${REPO_DIRS[@]}"; do
  echo "  ✔ https://github.com/$GH_OWNER/$name"
done

# Escribe/actualiza el nombre del repositorio en secrets.txt
# Mapea cada carpeta local a su clave correspondiente.
clave_para_repo() {
  case "$1" in
    ep02_ing_devops_database) echo "GITHUB_DATABASE" ;;
    ep02_ing_devops_backend)  echo "GITHUB_BACKEND" ;;
    ep02_ing_devops_frontend) echo "GITHUB_FRONTEND" ;;
    *) echo "" ;;
  esac
}

# Asigna el valor de una clave en secrets.txt (la crea si no existe)
set_secret_valor() {
  local key="$1"
  local value="$2"
  local file="$3"
  [ -f "$file" ] || touch "$file"
  local tmp
  tmp="$(mktemp)"
  awk -F'=' -v key="$key" -v val="$value" '
    BEGIN { found = 0 }
    {
      k = $1
      gsub(/[[:space:]]/, "", k)
      if (toupper(k) == toupper(key)) {
        print key "=" val
        found = 1
        next
      }
      print
    }
    END {
      if (!found) print key "=" val
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

banner "ACTUALIZANDO $SECRETS_FILE"
for name in "${REPO_DIRS[@]}"; do
  key="$(clave_para_repo "$name")"
  if [ -n "$key" ]; then
    url="https://github.com/$GH_OWNER/$name"
    set_secret_valor "$key" "$url" "$SECRETS_FILE"
    echo "  ✔ $key=$url"
  fi
done

echo ""
echo "PROCESO COMPLETADO"
