# Laboratorio Deploy a AWS

Guía por etapas para desplegar una aplicación de tres capas en AWS (EKS), operarla con CI/CD y observarla en la nube.

> 🎯 **Objetivo general:** al finalizar, el estudiante habrá llevado una aplicación desde su ejecución local hasta un despliegue automatizado en Kubernetes con calidad verificada en pipeline y monitoreo/observabilidad en Cloud.

| Paso | Tema | Duración estimada | Entregable |
|---|---|---|---|
| 01 | Credenciales (`secrets.txt`) | 10 min | Archivo con credenciales (nunca se sube a Git) |
| 02 | Aplicación local | 30–40 min | 3 contenedores corriendo + repos GitHub creados |
| 03 | Contenedor de operación | 15 min | Contenedor `devops-eks-lab` con sesión AWS activa |
| 04 | Repositorios GitHub | 5 min | 3 repos creados |
| 05 | Infraestructura K8s | 25–35 min | VPC + EKS + nodos `Ready` + reporte |
| 06 | ECR | 20–30 min | 3 imágenes publicadas |
| 07 | Despliegue K8s | 15–20 min | Pods `Ready` + URL pública |
| 08 | Secrets de GitHub | 5–10 min | Secrets configurados en los 3 repos |
| 09 | CI/CD | 30–45 min | Pipelines ✅ y app desplegada por Actions |
| 10 | Observabilidad (Semana 14) | 45–60 min | Alarmas en CloudWatch + demos con evidencia |

## Paso 01 Credenciales

Se debe crear un archivo llamado `secrets.txt` donde dejaremos todo lo necesario para automatizar las distintas operaciones que realizaremos:

Archivo: secrets.txt

```
aws_access_key_id=
aws_secret_access_key=
aws_session_token=
WSAccountId=
SONAR_TOKEN=
SNYK_TOKEN=
AWS_REGION=us-east-1
GITHUB_TOKEN=
GITHUB_DATABASE=
GITHUB_BACKEND=
GITHUB_FRONTEND=
```

> ⚠️ Este archivo contiene credenciales reales. Está en `.gitignore` y **nunca** debe subirse al repositorio.

## Paso 02 Aplicación

Se debe seleccionar una aplicación con tres capas que se pueda utilizar para esta implementación. Se puede utilizar este mismo código: ir a leer y aplicar el paso a paso que está en

[README.md](bloque00-aplicacion/README.md)

## Paso 03 Máquina Ubuntu para operar con AWS

Se debe ingresar a Docker Desktop y luego ejecutar una imagen de linux especialmente preparada.

Requisito previo

```bash
docker build -t devops-eks-lab .
```

Debes estar dentro del contenedor Docker `devops-eks-lab` con las credenciales de AWS Academy configuradas:

```bash
# Desde macOS / Linux (fuera del contenedor):
docker run -it -v "$(pwd)":/root/work devops-eks-lab
```

```powershell
# Desde Windows PowerShell (fuera del contenedor):
docker run -it -v ${PWD}:/root/work devops-eks-lab
```

## Paso 04 Creación de repositorios

Ahora vamos a crear los repositorios de forma automática en GitHub:

```
cd /root/work/bloque00-aplicacion
bash  crear_repos.sh
```

## Paso 05 Infra K8s

Ahora vamos a crear la infraestructura, que tiene VPC, EKS y grupos de nodos. El paso a paso está en:

[README.md](bloque01-infra-k8s/README.md)

## Paso 06 ECR

En el archivo `bloque02-ecr/repositorios.yaml` se debe poner el nombre del repo que tendrá cada imagen. Recomendación: dejar que comience con `ep02-` y así mantener un patrón que más adelante se usará.

[README.md](bloque02-ecr/README.md)

## Paso 07 K8s

Ahora aplicaremos las configuraciones para todas las aplicaciones.

Se debe cambiar los datos de dónde estarán las imágenes de ECR, y eso se hace modificando este archivo: `bloque03-k8s/values.yaml`

[README.md](bloque03-k8s/README.md)

## Paso 08 GitHub secrets

Este paso permite crear en forma automática las variables necesarias para que opere el pipeline. Los repositorios deben estar creados en GitHub.

[README.md](bloque04-github-secret/README.md)

## Paso 09 GitHub repos

Ahora vamos a ir a GitHub y clonaremos cada proyecto. Debe hacerse clone de cada proyecto:

[README.md](bloque05-github-repos/README.md)

## Paso 10 Observabilidad (Semana 14)

Convertimos el laboratorio en una sala de control: métrica personalizada del microservicio en CloudWatch, alarmas con notificación SNS, y dos demos en vivo (borrar pods y ver la auto-reparación; prueba de carga para que el HPA escale y salten las alarmas). Incluye opcional de service mesh con Istio + Kiali.

[README.md](bloque06-observabilidad/README.md)

## Entregables de evidencia (para el informe)

| Paso | Evidencia esperada | Dónde se genera |
|---|---|---|
| 05 | Nodos `Ready`, stack `CREATE_COMPLETE` | `bloque01-infra-k8s/reports/` |
| 07 | Pods `Running` y URL del LoadBalancer | `url-app.sh` |
| 09 | Pipeline de calidad y deploy en verde | GitHub Actions de cada repo |
| 10 | Captura de alarmas en `ALARM`/`OK`, timeline de auto-reparación, tabla de carga | `bloque06-observabilidad/reports/` |

Para ver la solucion andando:

```
cd /root/work/
bash url-app.sh
```
