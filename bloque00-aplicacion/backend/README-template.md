# README-template — Backend API (202601_ep03_backend)

> **Instrucciones:** Completa cada sección con las evidencias generadas en los reportes de `bloque06/docs/reports/`.  
> Las capturas de pantalla van en la carpeta `docs/`.  
> Marca con `[x]` los ítems que ya tengas.

---

## 📝 Descripción del proyecto

<!-- Describe brevemente qué hace este backend: tecnología, endpoints principales, base de datos que usa -->

**Tecnología:** Node.js + Express  
**Puerto:** 3001  
**Base de datos:** PostgreSQL (ep03-db:3306)  
**Endpoints:**

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/health` | Health check |
| GET | `/api/productos` | Listar productos |
| <!-- completar --> | | |

---

## 🏗️ Arquitectura

<!-- Inserta tu diagrama de arquitectura -->

![Diagrama de arquitectura](docs/arquitectura.png)

### Componentes del clúster

| Componente | Valor |
|---|---|
| **Clúster EKS** | `laboratorio-ep03-eks` (ACTIVE, v1.33) |
| **NodeGroup** | SPOT t3.large, min=1, max=3 |
| **VPC** | 10.0.0.0/16 — 6 subnets |
| **Service tipo** | ClusterIP (solo interno) |
| **DNS interno** | `ep03-backend:3001` |

### Evidencia de la configuración

<!-- Copia desde docs/reports/etapa04-CreaClusterEKS.md -->
<details>
<summary>📸 Ver evidencia del clúster EKS</summary>

```
$ kubectl get nodes
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-11-58.ec2.internal   Ready    <none>   42m   v1.33.11-eks-3385e9b
```

<!-- Pegar más evidencias aquí -->
</details>

---

## 🚀 Pipeline CI/CD

<!-- Inserta captura del pipeline exitoso -->

![Pipeline exitoso](docs/pipeline-success.png)

### Workflow

```yaml
# .github/workflows/deploy-backend-eks.yml
# Jobs: versioning → build-push-ecr → deploy
```

### Secrets requeridos

| Secret | Propósito |
|---|---|
| `AWS_ACCESS_KEY_ID` | Credenciales AWS |
| `AWS_SECRET_ACCESS_KEY` | Credenciales AWS |
| `AWS_SESSION_TOKEN` | Token STS (Learner Lab) |
| `AWS_REGION` | `us-east-1` |

### Tiempos del pipeline

<!-- Completar con datos de GitHub Actions -->

| Ejecución | Fecha | Versioning | Build & Push | Deploy | Total |
|---|---|---|---|---|---|
| #1 | <!-- fecha --> | <!-- seg --> | <!-- seg --> | <!-- seg --> | <!-- seg --> |
| #2 | <!-- fecha --> | <!-- seg --> | <!-- seg --> | <!-- seg --> | <!-- seg --> |
| #3 | <!-- fecha --> | <!-- seg --> | <!-- seg --> | <!-- seg --> | <!-- seg --> |
| **Promedio** | | <!-- seg --> | <!-- seg --> | <!-- seg --> | <!-- seg --> |

---

## 🔧 Manifiestos Kubernetes

| Archivo | Propósito |
|---|---|
| `k8s/namespace.yaml` | Namespace `ep03` |
| `k8s/backend-deployment.yaml` | Deployment con 2 réplicas, RollingUpdate, health checks |
| `k8s/backend-service.yaml` | Service tipo ClusterIP (puerto 3001) |
| `k8s/backend-hpa.yaml` | HPA: min=2, max=10, CPU 70% |

### Variables de entorno

| Variable | Fuente | Valor |
|---|---|---|
| `DB_HOST` | Hardcodeada | `ep03-db` |
| `DB_USER` | Hardcodeada | `root` |
| `DB_PASSWORD` | `secretKeyRef` → `postgres-secret` | `MYSQL_ROOT_PASSWORD` |
| `DB_NAME` | Hardcodeada | `ep03_data` |

---

## 📊 Autoscaling (HPA)

### Configuración

```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Justificación del umbral

<!-- Explica por qué elegiste 70% (o el valor que usaste) -->

**Mi justificación:** <!-- completar -->

### Evidencia de funcionamiento

<!-- Copiar desde docs/reports/etapa09-ValidaApp.md o ejecutar: kubectl get hpa -n ep03 -->

```
$ kubectl get hpa -n ep03
NAME                  REFERENCE          TARGETS       MINPODS MAXPODS REPLICAS
ep03-backend-hpa    Deployment/backend cpu: 1%/70%   2       10      2
```

<!-- Inserta captura del HPA -->

![HPA funcionando](docs/hpa-evidence.png)

---

## 🔐 Secrets y credenciales

### GitHub Secrets

| Secret | Propósito |
|---|---|
| `AWS_ACCESS_KEY_ID` | Credenciales AWS (Learner Lab) |
| `AWS_SECRET_ACCESS_KEY` | Credenciales AWS |
| `AWS_SESSION_TOKEN` | Token STS (obligatorio) |
| `AWS_REGION` | `us-east-1` |

### Kubernetes Secrets

La contraseña de PostgreSQL se inyecta via `secretKeyRef` desde `postgres-secret`.  
Nunca está expuesta en logs ni en el código.

---

## ✅ Validación funcional

### Pods Running

<!-- Copiar desde docs/reports/etapa09-ValidaApp.md o ejecutar: kubectl get pods -n ep03 -->

```
$ kubectl get pods -n ep03 -l app=ep03-backend
NAME                              READY   STATUS    RESTARTS   AGE
ep03-backend-6d7789595b-dcz55   1/1     Running   0          34m
ep03-backend-6d7789595b-hdv6g   1/1     Running   0          34m
```

### Health check

```
$ curl -s http://ep03-backend:3001/api/health
{"status":"ok","timestamp":"..."}
```

### Auto-healing

<!-- Copiar desde docs/reports/paso12_healing/healing.sh output -->

```
$ kubectl delete pod ep03-backend-6d7789595b-dcz55 -n ep03
pod "ep03-backend-6d7789595b-dcz55" deleted

$ kubectl get pods -n ep03 -w
ep03-backend-6d7789595b-xk9m2   Running   ← recreado en ~5s
```

---

## 📈 Logs y métricas

### Logs de la aplicación

```
$ kubectl logs deployment/ep03-backend -n ep03 --tail=10
Server running on port 3001
Connected to PostgreSQL database: ep03_data
GET /api/health 200 2.101 ms
```

### Métricas de CloudWatch

<!-- Inserta captura de CloudWatch logs -->

![CloudWatch logs](docs/cloudwatch-logs.png)

### Análisis de tiempos

<!-- Completar con la tabla de tiempos y conclusiones -->

**Conclusiones:**
1. <!-- completar -->
2. <!-- completar -->
3. **Mejora propuesta:** <!-- completar -->

---

## 🐛 Problemas conocidos

| Problema | Causa | Solución |
|---|---|---|
| `ImagePullBackOff` al primer deploy | La imagen tarda en estar disponible en ECR | `kubectl rollout status` espera hasta 120s |
| Credenciales AWS expiran | Learner Lab renueva credenciales STS | Actualizar secrets en GitHub Settings |

---

## 📋 Checklist de verificación

- [ ] README completo
- [ ] Capturas de pantalla en `docs/`
- [ ] Pipeline ✅ visible en GitHub Actions
- [ ] Commits descriptivos
- [ ] URL pública del frontend funcionando
- [ ] Logs de la aplicación visibles

---

*Template para README del backend — ISY1101 EP3*
