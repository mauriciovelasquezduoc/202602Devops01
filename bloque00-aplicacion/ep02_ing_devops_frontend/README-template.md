# README-template — Frontend Web (202601_ep02_frontend)

> **Instrucciones:** Completa cada sección con las evidencias generadas en los reportes de `bloque06/docs/reports/`.  
> Las capturas de pantalla van en la carpeta `docs/`.

---

## 📝 Descripción del proyecto

<!-- Describe brevemente qué hace este frontend: tecnología, cómo consume al backend, etc. -->

**Tecnología:** HTML/CSS/JS estático servido con Nginx  
**Puerto:** 80  
**Backend que consume:** `http://ep02-backend:3001` (DNS interno de Kubernetes)  
**Expuesto mediante:** Service tipo LoadBalancer (URL pública)

---

## 🏗️ Arquitectura

| Componente | Valor |
|---|---|
| **Clúster EKS** | `laboratorio-ep02-eks` (ACTIVE) |
| **Service tipo** | LoadBalancer (público, internet-facing) |
| **Puerto contenedor** | 80 |
| **Anotación** | `service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing` |

<!-- Inserta captura del service -->

```
$ kubectl get svc -n ep02 -l app=ep02-frontend
NAME               TYPE           CLUSTER-IP    EXTERNAL-IP
ep02-frontend    LoadBalancer   172.20.123.7  a5d87d...us-east-1.elb.amazonaws.com
```

---

## 🚀 Pipeline CI/CD

<!-- Inserta captura del pipeline exitoso -->

![Pipeline exitoso](docs/pipeline-success.png)

### Tiempos del pipeline

<!-- Completar con datos de GitHub Actions -->

| Ejecución | Fecha | Versioning | Build & Push | Deploy | Total |
|---|---|---|---|---|---|
| #1 | <!-- fecha --> | <!-- seg --> | <!-- seg --> | <!-- seg --> | <!-- seg --> |
| Promedio | | <!-- seg --> | <!-- seg --> | <!-- seg --> | <!-- seg --> |

---

## 🔧 Manifiestos Kubernetes

| Archivo | Propósito |
|---|---|
| `k8s/frontend-deployment.yaml` | Deployment con 2 réplicas, RollingUpdate |
| `k8s/frontend-service.yaml` | Service tipo LoadBalancer (puerto 80) |
| `k8s/frontend-hpa.yaml` | HPA: min=2, max=6, CPU 60% |

### Health checks

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 3
  periodSeconds: 5
```

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
        averageUtilization: 60
```

### Evidencia

```
$ kubectl get hpa ep02-frontend-hpa -n ep02
NAME                   REFERENCE           TARGETS       MINPODS MAXPODS REPLICAS
ep02-frontend-hpa    Deployment/frontend cpu: 2%/60%   2       6       2
```

---

## ✅ Validación funcional

### URL pública

<!-- Completa con la URL de tu LoadBalancer -->

```
http://a5d87d388be4c440192b1e41aebf7073-1319560992.us-east-1.elb.amazonaws.com
```

<!-- Inserta captura de la app funcionando en el navegador -->

![App funcionando](docs/app-screenshot.png)

### Auto-healing

```
$ kubectl delete pod ep02-frontend-757984d475-fs467 -n ep02
pod eliminado... recreado en ~5s ✅
```

### Logs

```
$ kubectl logs deployment/ep02-frontend -n ep02 --tail=5
...
```

---

## 📈 Métricas

```
$ kubectl top pods -n ep02 -l app=ep02-frontend
NAME                               CPU(cores)   MEMORY(bytes)
ep02-frontend-757984d475-fs467   2m           64Mi
ep02-frontend-757984d475-l56nj   3m           58Mi
```

---

## 📋 Checklist

- [ ] README completo
- [ ] Captura de la app funcionando en navegador
- [ ] URL pública documentada
- [ ] Pipeline ✅ en GitHub Actions
- [ ] Logs de la aplicación visibles

---

*Template para README del frontend — ISY1101 EP3*
