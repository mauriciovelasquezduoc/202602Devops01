#!/bin/bash
set -e

# =====================================================
# Script: crear_repos.sh
# Crea en GitHub los 3 repositorios de la aplicación a
# partir de las carpetas locales y los sube (push).
#
# Modelo de ramas (laboratorio multi-ambiente):
#   development  -> rama de trabajo (push directo, por defecto)
#   quality      -> PROTEGIDA: solo cambia vía Pull Request
#   production   -> PROTEGIDA: solo cambia vía Pull Request
#   main         -> se elimina (ya no existe en estos repos)
#
# Reglas de protección para quality y production:
#   - Se requiere Pull Request (no push directo, sin force push,
#     sin delete, historial lineal)
#   - Se requieren los checks del workflow "Calidad de código"
#   - Se requiere 1 review de aprobación
#   - enforce_admins: configurable (ver PROTECCION_INCLUIR_ADMINS abajo)
#
# Sobre repositorios NUEVOS: se crean desde la rama development.
# Sobre repositorios EXISTENTES (creados antes con main): se
# crea development desde lo que tenía main, se cambia la rama
# por defecto y se borra main.
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
BRANCHES_EXTRA=("quality" "production")   # se crean desde development
BRANCHES_PROTEGIDAS=("quality" "production")

# Reglas de protección (señaladas en el plan del laboratorio):
#   REVIEW_REQUERIDOS = 0..6   reviews de aprobación exigidas al PR
#   PROTECCION_INCLUIR_ADMINS=false permite que el dueño del repo
#   mergeé sus propios PR sin review (útil si operas solo); con true
#   la regla es total pero necesitas otro usuario que apruebe.
REVIEW_REQUERIDOS="${REVIEW_REQUERIDOS:-1}"
if [ "${PROTECCION_INCLUIR_ADMINS:-true}" = "true" ]; then
  INCLUIR_ADMINS_JSON="true"
else
  INCLUIR_ADMINS_JSON="false"
fi

# ── Required status checks: jobs del workflow "Calidad de código"
# (el nombre del check en GitHub es el del JOB, no el del workflow)
checks_para_repo() {
  case "$1" in
    *database*)
      printf '%s\n' \
        "Imagen Postgres (build + Trivy + smoke test)"
      ;;
    *backend*)
      printf '%s\n' \
        "Spotless (formato de código)" \
        "Checkstyle (convenciones de código)" \
        "PMD (code smells)" \
        "SpotBugs (bugs en el bytecode)" \
        "Pruebas unitarias (JUnit + Mockito)" \
        "Mutación (PIT)" \
        "JaCoCo (cobertura de pruebas)" \
        "SonarQube (calidad)" \
        "Snyk (seguridad de dependencias)" \
        "Cucumber (BDD / integración)" \
        "Contenedor (Docker + Trivy)" \
        "DAST (OWASP ZAP)" \
        "Rendimiento (Gatling)" \
        "Rendimiento (JMeter)"
      ;;
    *frontend*)
      printf '%s\n' \
        "Prettier (formato de código)" \
        "ESLint (lint / convenciones)" \
        "Pruebas unitarias (Vitest)" \
        "Cobertura (Vitest v8)" \
        "Mutación (Stryker)" \
        "SonarCloud (calidad)" \
        "Snyk (seguridad de dependencias)" \
        "Contenedor (Docker + Trivy)" \
        "DAST (OWASP ZAP)" \
        "Rendimiento (Lighthouse)"
      ;;
  esac
}

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

# Construye el JSON de protección en $1 (archivo destino).
build_protection_json() {
  local outfile="$1"
  local contexts="["
  local first=1
  local chk
  while IFS= read -r chk; do
    [ -n "$chk" ] || continue
    if [ $first -eq 1 ]; then first=0; else contexts="$contexts,"; fi
    contexts="$contexts\"$chk\""
  done < <(checks_para_repo "${REPO_ACTUAL}")
  contexts="$contexts]"

  cat > "$outfile" <<EOF
{
  "required_status_checks": {
    "strict": false,
    "contexts": $contexts
  },
  "enforce_admins": $INCLUIR_ADMINS_JSON,
  "required_pull_request_reviews": {
    "required_approving_review_count": $REVIEW_REQUERIDOS,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
}

banner "CREACIÓN DE REPOSITORIOS EN GITHUB (3 ramas + protecciones)"

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

# Aplica (o actualiza) la protección de una rama protegida.
proteger_rama() {
  local full_name="$1"
  local branch="$2"
  local rules_file
  rules_file="$(mktemp)"
  build_protection_json "$rules_file"

  printf '  Protegiendo %s: required_status_checks=%s reviews=%s enforce_admins=%s ... ' \
    "$branch" "$(wc -l < <(checks_para_repo "${REPO_ACTUAL}") | tr -d ' ')" \
    "$REVIEW_REQUERIDOS" "$INCLUIR_ADMINS_JSON"

  if gh api \
    -X PUT "repos/$full_name/branches/$branch/protection" \
    --input "$rules_file" > /dev/null 2> /tmp/gh-protect-err.txt; then
    echo "OK"
  else
    echo ""
    echo "  ERROR al proteger $branch:"
    sed 's/^/      /' /tmp/gh-protect-err.txt
    echo "      (En repos privados de plan free los checks/reviews no están"
    echo "       disponibles: hazlo en repos PÚBLICOS o revisa el permiso del token)"
  fi
  rm -f "$rules_file" /tmp/gh-protect-err.txt
}

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
          git checkout development > /dev/null 2>&1
          git -c credential.helper="$GIT_CRED_HELPER" merge --ff-only origin/main > /dev/null 2>&1 || \
            echo "ADVERTENCIA: development local y origin/main divergen (se continúa con development local)."
        else
          echo "Creando development local a partir de origin/main..."
          git checkout -B development origin/main > /dev/null 2>&1
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

    # 5) Crear el repo si no existe (development queda como rama por defecto)
    if [ "$existe_remoto" -eq 0 ]; then
      echo "Creando repositorio $full_name (desde $DEFAULT_BRANCH)..."
      gh repo create "$GH_OWNER/$name" \
        --public \
        --source=. \
        --remote=origin \
        --push > /dev/null
    else
      echo "Publicando $DEFAULT_BRANCH..."
      git -c credential.helper="$GIT_CRED_HELPER" push -u origin "$DEFAULT_BRANCH"
    fi

    # 6) Crear quality y production desde el MISMO commit de development
    #    (solo si no existen; no se aplasta historial ajeno)
    for br in "${BRANCHES_EXTRA[@]}"; do
      if ! git show-ref --verify --quiet "refs/heads/$br"; then
        git branch "$br" "$DEFAULT_BRANCH"
      fi
      if git ls-remote --heads origin "$br" | grep -q "$br"; then
        echo "Rama $br ya existe en el remoto (sin cambios)"
      else
        git -c credential.helper="$GIT_CRED_HELPER" push origin "$br"
        echo "Rama $br creada en el remoto"
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
  if git ls-remote --heads origin main | grep -q "refs/heads/main"; then
    echo "Borrando main en el remoto..."
    git -C "$dir" -c credential.helper="$GIT_CRED_HELPER" push origin --delete main
    echo "  main eliminada en el remoto"
  fi
  if git -C "$dir" show-ref --verify --quiet refs/heads/main; then
    git -C "$dir" branch -D main > /dev/null 2>&1 || true
    echo "  main eliminada localmente"
  fi

  # 9) Proteger quality y production con las reglas señaladas
  for br in "${BRANCHES_PROTEGIDAS[@]}"; do
    proteger_rama "$full_name" "$br"
  done

  echo "  ✔ https://github.com/$GH_OWNER/$name"
done

banner "RESUMEN"
for name in "${REPO_DIRS[@]}"; do
  echo "  ✔ https://github.com/$GH_OWNER/$name"
  echo "      Ramas: development (por defecto) | quality (protegida) | production (protegida)"
  echo "      main: eliminada"
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
