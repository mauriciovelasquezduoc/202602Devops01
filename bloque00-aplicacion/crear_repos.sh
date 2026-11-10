#!/bin/bash
set -e

# =====================================================
# Script: crear_repos.sh
# Crea en GitHub los 3 repositorios de la aplicación a
# partir de las carpetas locales y los sube (push).
#
# Modelo de ramas (una sola rama de trabajo):
#   development  -> única rama del repo (push directo, por defecto)
#
# Al final del proceso solo existirá development: si quality o
# production (o main) existen, se eliminan (local y remota).
#
# Sobre repositorios NUEVOS: se crean desde la rama development.
# Sobre repositorios EXISTENTES: con la política de recreación
# (RECREAR="si", o CREAR_SIN_PREGUNTAR=1, o responder 'si' a la
# pregunta) se ELIMINAN en GitHub y se recrean desde cero usando
# el contenido de la carpeta local (el historial remoto se pierde).
# Si se responde 'no' (modo migración): se crea development desde
# lo que tenía main, se cambia la rama por defecto y se borra main.
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

# ── Modelo de ramas ──────────────────────────────────────────
DEFAULT_BRANCH="development"
# Ramas de modelos anteriores que ya no se usan: se eliminan
# (local y remota) para que solo exista development.
RAMAS_OBSOLETAS=("quality" "production")

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

banner "CREACIÓN DE REPOSITORIOS EN GITHUB (solo development)"

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
export GH_TOKEN="$GITHUB_TOKEN"
echo "Usando GITHUB_TOKEN para autenticar..."

# Helper efímero para git fetch/push https (NO persiste el token en disco).
export GIT_TERMINAL_PROMPT=0
GIT_CRED_HELPER='!f() { echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f'
export GITHUB_TOKEN

GH_OWNER="$(gh api user -q '.login')"
echo "Usuario GitHub: $GH_OWNER"

# ── Política de recreación ───────────────────────────────────
# Si el repositorio YA existe en GitHub se ELIMINA y se vuelve
# a crear (historial remoto perdido). Requiere token con scope
# delete_repo. Se puede omitir la pregunta con CREAR_SIN_PREGUNTAR=1.
if [ -n "${CREAR_SIN_PREGUNTAR:-}" ]; then
  RECREAR="si"
else
  echo ""
  echo "ATENCIÓN: esta política ELIMINA en GitHub cualquier repo que"
  echo "ya exista (historial, ramas e issues se pierden)"
  echo "y lo recrea desde las carpetas locales."
  printf '¿Continuar? [si/no]: '
  read -r respuesta
  case "$respuesta" in
    [Ss] | [Ss][Ii] | [Yy] | [Yy][Ee][Ss]) RECREAR="si" ;;
    *) RECREAR="no"; echo "Se conservará el contenido de repos existentes (modo migración)." ;;
  esac
fi

# Crear y configurar cada repositorio
for name in "${REPO_DIRS[@]}"; do
  dir="${SCRIPT_DIR}/${name}"
  REPO_ACTUAL="$name"
  full_name="$GH_OWNER/$name"
  banner "Repositorio: $name"

  if [ ! -d "$dir" ]; then
    echo "ADVERTENCIA: No existe la carpeta $dir (omitido)"
    continue
  fi

  existe_remoto=0
  if gh repo view "$GH_OWNER/$name" > /dev/null 2>&1; then
    existe_remoto=1
    echo "El repositorio $full_name ya existe en GitHub."
    if [ "$RECREAR" = "si" ]; then
      echo "Eliminando $full_name en GitHub (política de recreación)..."
      codigo=$(curl -s -o /tmp/gh-delete-repo.txt -w '%{http_code}' -X DELETE \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        "https://api.github.com/repos/$full_name")
      if [ "$codigo" = "204" ]; then
        existe_remoto=0
        echo "  Repositorio eliminado. Se creará de nuevo desde la carpeta local."
        echo "  Restableciendo repositorio git local desde cero..."
        rm -rf "$dir/.git"
      else
        echo ""
        echo "ERROR: no se pudo eliminar $full_name (HTTP $codigo):"
        grep -o '"message":[^,]*' /tmp/gh-delete-repo.txt | head -1 | sed 's/^/    /'
        echo "    (El token necesita scope delete_repo. Usa CREAR_SIN_PREGUNTAR=1"
        echo "     para omitir la pregunta, o responde 'no' para modo migración.)"
        echo "    Continuando en modo migración sobre el repo existente..."
        existe_remoto=1
      fi
      rm -f /tmp/gh-delete-repo.txt
    fi
  else
    echo "El repositorio $full_name no existe: se creará nuevo."
  fi

  (
    cd "$dir"

    # 1) Repositorio git local + rama por defecto
    if [ ! -d .git ]; then
      echo "Inicializando repositorio git en $DEFAULT_BRANCH..."
      git init -b "$DEFAULT_BRANCH" > /dev/null 2>&1 || git init > /dev/null
    fi

    # Identidad git local de respaldo (útil en contenedores sin config global)
    if ! git config user.email > /dev/null 2>&1; then
      git config user.email "${GH_OWNER}@users.noreply.github.com"
      git config user.name "${GH_OWNER}"
    fi

    # 2) Remoto origin siempre apuntando al repo correcto
    remote_url="https://github.com/$GH_OWNER/$name.git"
    if git remote get-url origin > /dev/null 2>&1; then
      git remote set-url origin "$remote_url"
    else
      git remote add origin "$remote_url"
    fi

    # 3) Si el remoto existe, traemos su estado y baseamos development
    #    en origin/main (para repos creados antes con main).
    if [ "$existe_remoto" -eq 1 ]; then
      echo "Fetch del remoto..."
      git -c credential.helper="$GIT_CRED_HELPER" fetch origin --prune > /dev/null 2>&1 || {
        echo "ERROR: no se pudo hacer fetch de $remote_url"
        exit 1
      }

      if git show-ref --verify --quiet refs/remotes/origin/main; then
        # Repos legados: development nace de lo que era main.
        if git show-ref --verify --quiet refs/heads/development; then
          git checkout development || { echo "ERROR: no se pudo checkout development"; exit 1; }
          git -c credential.helper="$GIT_CRED_HELPER" merge --ff-only origin/main > /dev/null 2>&1 || \
            echo "ADVERTENCIA: development local y origin/main divergen (se continúa con development local)."
        else
          echo "Creando development local a partir de origin/main..."
          if ! git checkout -B development origin/main; then
            # Untracked locales chocan con el contenido de origin/main: se
            # asienta development en origin/main SIN tocar el árbol de trabajo
            # (los cambios locales se conservan y se commitean en el paso 4).
            git update-ref "refs/heads/$DEFAULT_BRANCH" refs/remotes/origin/main
            echo "  (checkout omitido por archivos locales en conflicto; se asentó" \
                 "development en origin/main sin modificar el directorio de trabajo)"
          fi
        fi
      fi

      # Si estábamos en main (ya migrado), cambiar a development.
      if [ "$(git branch --show-current)" != "$DEFAULT_BRANCH" ]; then
        if git show-ref --verify --quiet refs/heads/development; then
          git checkout development > /dev/null 2>&1
        else
          git branch -m "$(git branch --show-current)" development
        fi
      fi
    fi

    # 4) Commit del contenido actual (si hay cambios)
    git add -A
    if git diff --cached --quiet; then
      echo "Sin cambios para commitear"
    else
      git commit -q -m "Initial commit: $name"
      echo "Commit creado en $DEFAULT_BRANCH"
    fi

    # 5) Crear el repo vacío si no existe (el remoto origin ya está en el
    #    paso 2; el push de development queda como rama por defecto).
    #    Con reintentos: GitHub aplica "secondary rate limit" si se crean
    #    varios repos en poco tiempo y falla con 403/422.
    if [ "$existe_remoto" -eq 0 ]; then
      echo "Creando repositorio $full_name (vacío, el contenido se sube a continuación)..."
      intentos=0
      max_intentos="${CREAR_REPO_MAX_INTENTOS:-12}"
      espera_segundos="${CREAR_REPO_ESPERA:-60}"
      creado=0
      while [ "$intentos" -lt "$max_intentos" ]; do
        intentos=$((intentos + 1))
        if gh repo create "$GH_OWNER/$name" --public > /dev/null 2> /tmp/gh-create-repo-err.txt; then
          creado=1
          break
        fi
        if grep -qi "too quickly\|rate limit\|temporarily\|try again later" /tmp/gh-create-repo-err.txt; then
          echo "  GitHub limitando creación (abuse/rate limit). Reintento $intentos/$max_intentos en $espera_segundos s..."
          sleep "$espera_segundos"
        else
          break
        fi
      done
      rm -f /tmp/gh-create-repo-err.txt
      if [ "$creado" -eq 0 ]; then
        echo "ERROR: no se pudo crear $full_name en GitHub tras $intentos intento(s)."
        echo "  Espera unos minutos y vuelve a ejecutar el script (los pasos son idempotentes)."
        exit 1
      fi
    fi
    echo "Publicando $DEFAULT_BRANCH..."
    git -c credential.helper="$GIT_CRED_HELPER" push -u origin "$DEFAULT_BRANCH"

    # 6) Limpieza: eliminar ramas del modelo anterior (quality,
    #    production) para que solo exista development
    for br in "${RAMAS_OBSOLETAS[@]}"; do
      git branch -D "$br" > /dev/null 2>&1 || true
      if git ls-remote --heads origin "$br" | grep -q "refs/heads/$br"; then
        # Si la rama está protegida, git rechaza el borrado (GH006):
        # se quita la protección primero y luego se elimina la rama.
        curl -s -o /dev/null -X DELETE \
          -H "Authorization: Bearer $GITHUB_TOKEN" \
          "https://api.github.com/repos/$full_name/branches/$br/protection" > /dev/null
        if git -c credential.helper="$GIT_CRED_HELPER" push origin --delete "$br" > /dev/null 2>&1; then
          echo "Rama $br eliminada del remoto"
        else
          echo "ADVERTENCIA: no se pudo eliminar $br del remoto (revisa permisos)."
        fi
      fi
    done
  )

  # 7) Rama por defecto = development (necesario ANTES de borrar main)
  default_actual="$(gh api "repos/$full_name" -q '.default_branch')"
  if [ "$default_actual" != "$DEFAULT_BRANCH" ]; then
    echo "Cambiando rama por defecto: $default_actual -> $DEFAULT_BRANCH"
    gh api -X PATCH "repos/$full_name" -f "default_branch=$DEFAULT_BRANCH" > /dev/null
  else
    echo "Rama por defecto: $DEFAULT_BRANCH (correcta)"
  fi

  # 8) Borrar main (remoto y local) — ya la reemplazó development
  main_en_remoto="$(git -C "$dir" -c credential.helper="$GIT_CRED_HELPER" \
    ls-remote --heads origin refs/heads/main 2>/dev/null || true)"
  if [ -n "$main_en_remoto" ]; then
    echo "Borrando main en el remoto..."
    git -C "$dir" -c credential.helper="$GIT_CRED_HELPER" push origin --delete main || \
      echo "  ADVERTENCIA: no se pudo borrar main del remoto (se continúa)."
  fi
  if git -C "$dir" show-ref --verify --quiet refs/heads/main; then
    git -C "$dir" branch -D main > /dev/null 2>&1 || true
    echo "  main eliminada localmente"
  fi

  echo "  ✔ https://github.com/$GH_OWNER/$name"
done

banner "RESUMEN"
for name in "${REPO_DIRS[@]}"; do
  echo "  ✔ https://github.com/$GH_OWNER/$name"
  echo "      Ramas: development (única, por defecto)"
  echo "      quality/production/main: eliminadas"
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
