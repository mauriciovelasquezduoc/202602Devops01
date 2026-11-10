# Bloque 06 — Monitoreo y Observabilidad en un entorno Cloud (Semana 14)

Este bloque convierte el laboratorio en una **sala de control**: publicamos métricas
personalizadas del microservicio en CloudWatch, creamos alarmas con notificación por
correo, y provocamos fallas y carga **en vivo** para ver cómo reacciona el sistema
(auto-reparación, HPA y alarmas). Opcionalmente instalamos **Istio + Kiali** para
observar el tráfico entre servicios.

## Objetivos de la semana (qué deberías lograr al final)

1. Completar lo pendiente en **CloudWatch**, configurando una **alarma o métrica
   personalizada** sobre el microservicio.
2. Explicar con tus palabras qué problema resuelve una **service mesh** y reconocer
   los términos *pod, service, VirtualService y Gateway*.
3. Relacionar **Kiali** con decisiones técnicas: visualizar tráfico, errores y
   conexiones entre servicios.
4. Distinguir las reglas de cumplimiento **del pipeline** (calidad/seguridad:
   SonarQube, Snyk, Trivy, JaCoCo — bloque05) de las que aporta **la malla de
   servicios** (mTLS, rutas, reintentos).

## Conceptos en 5 minutos

| Concepto | Idea en una frase |
|---|---|
| **Métrica** | Un número medido en el tiempo (CPU, pods activos, salud 0/1). Puede ser automática (EC2, ELB) o **personalizada** (`put-metric-data`) |
| **Alarma** | Una regla sobre una métrica ("si SaludBackend < 1 por 1 min → ALARM"). Ciclo de vida: `INSUFFICIENT_DATA → OK → ALARM → OK` |
| **SNS** | El "buzón" al que la alarma envía la notificación (correo) |
| **Estado deseado** | Kubernetes opera por reconciliación: si el mundo real no coincide con lo declarado (p. ej. Réplicas: 1), un controlador lo corrige **solo** |
| **Self-healing** | Auto-reparación: borra un pod y el ReplicaSet lo repone. Es el mismo mecanismo cuando un nodo muere |
| **HPA** | Escala el número de réplicas según CPU promedio; usa el Metrics Server (bloque01). Escala rápido, reduce con ~5 min de estabilización |
| **Service mesh** | Capa que intercepta el tráfico entre pods con un sidecar (Envoy) para controlar rutas, cifrar (mTLS) y medir, sin tocar el código |

## Prerequisitos

- Bloque03 aplicado: `kubectl get pods -n ep02` con backend, frontend y base de datos en `Running`.
- Sesión AWS activa (credenciales Academy) dentro del contenedor `devops-eks-lab`.
- Para la UI de Kiali (opcional): levantar el contenedor con `-p 20001:20001`.

## Flujo de la sesión

```bash
cd /root/work/bloque06-observabilidad

bash ejecutar.sh                 # 1. preparar: SNS + alarmas + métrica personalizada
bash demo-1-auto-reparacion.sh   # 2. borrar pods y ver la reconstrucción (T+ en vivo)
bash demo-2-prueba-carga.sh      # 3. carga HTTP: HPA escala y las alarmas saltan
bash demo-3-observatorio.sh      # 4. sala de control (dejar corriendo en otra terminal)
bash opcional-istio-kiali.sh     # 5. OPCIONAL: service mesh + visualización
```

> 💡 **Tip de clase:** abre 3 terminales del contenedor. En una corre `demo-3-observatorio.sh`,
> en otra las demos 1 y 2, y en la tercera van mirando `kubectl get hpa -n ep02 -w`.

## Demo 1 — Auto-reparación (borrar pods)

**Qué haces:** el script borra 1 pod del backend y 1 del frontend, y te muestra una
línea de tiempo (`T+0s, T+5s, ...`) hasta que ambos vuelven a `Ready`.

**Qué deberías observar:**

- El frontend (nginx, readiness inmediata) se recupera en **~5–15 s**.
- El backend tarda **~60–90 s**: su `readinessProbe` tiene `initialDelaySeconds: 50`.
  La aplicación puede estar viva y aun así "no lista" — así protege el balanceo.
- La métrica personalizada `SaludBackend` baja a `0` y las alarmas
  `ep02-backend-salud` / `ep02-backend-pods` pasan a `ALARM` (~1–2 min después).

**Evidencia para tu informe:** captura de la línea de tiempo (`reports/demo1-timeline-*.md`),
captura de la alarma en `ALARM`, y el tiempo de recuperación calculado.

## Demo 2 — Prueba de carga (HPA + alarmas)

**Qué haces:** el script dispara peticiones HTTP reales contra la URL pública
(`http://<LB>/ep02/actuator/health`) con 8 procesos durante 5 minutos, mientras imprime
cada 15 s el estado de los HPA y la CPU de los pods.

**Qué deberías observar:**

- `TARGETS` de `ep02-backend-hpa` sube hacia 70% y `REPLICAS` pasa de 1 a 2, 3... (máx 10).
- La CPU del nodo (t3.large) sube: si cruza 60% sostenida, salta `ep02-cpu-nodo-alta`.
- Si saturas el backend, el balanceador acumula 5XX y salta `ep02-elb-5xx`.
- Al terminar la carga, `REPLICAS` **no baja de inmediato**: espera el periodo de
  estabilización (~5 min). Con `ESPERAR_BAJADA=1` el script se queda a presenciarlo.

**Evidencia:** tabla resumen del script (`reports/demo2-carga-*.md`), `kubectl get hpa`
antes/durante/después, y el estado de las alarmas al final.

## Demo 3 — Observatorio

Refresca cada 15 s el estado de todas las alarmas `ep02-*` y el histórico de la métrica
`SaludBackend`. Déjalo corriendo mientras haces las otras demos: verás en vivo el ciclo
`OK → ALARM → OK`.

También puedes ir a la consola: **CloudWatch → Alarms** y **CloudWatch → Metrics →
Custom namespaces → Ep02/Microservicio**.

## Alarmas creadas por este bloque

| Alarma | Métrica | Condición | Se dispara cuando... |
|---|---|---|---|
| `ep02-backend-salud` | **personalizada** `Ep02/Microservicio` SaludBackend | `< 1` por 1 min | el backend deja de responder `/actuator/health` |
| `ep02-backend-pods` | **personalizada** `PodsActivos` | `< 1` por 1 min | quedan 0 pods Ready del backend |
| `ep02-cpu-nodo-alta-*` | automática `AWS/EC2 CPUUtilization` | `>= 60%` por 2 min | el nodo se satura (demo de carga) |
| `ep02-elb-5xx` | automática `AWS/ELB HTTPCode_ELB_5XX` | `>= 5` por min | el balanceador recibe errores del backend |

Las alarmas notifican al topic SNS `ep02-alertas` si registraste tu correo en `ejecutar.sh`
(recuerda **confirmar la suscripción** desde el email que llega).

## Opcional — Istio + Kiali (service mesh)

`opcional-istio-kiali.sh` instala el perfil demo de Istio, inyecta el sidecar Envoy en
`ep02`, instala Prometheus + Kiali y crea un **Gateway** y un **VirtualService** que
exponen la app a través de la malla. Después de generar tráfico (demo 2), abre Kiali
(`kubectl port-forward svc/kiali -n istio-system 20001:20001` → `http://localhost:20001`)
y en **Traffic Graph** observa: quién habla con quién, tasas de error y rutas.

- **VirtualService**: la regla ("todo el HTTP del gateway va a `ep02-frontend:80`").
- **Gateway**: la puerta de entrada de la malla hacia Internet.
- Limpieza: `LIMPIAR=1 bash opcional-istio-kiali.sh`.

## Preguntas de reflexión (para tus conclusiones)

1. ¿Cuánto tardó en recuperarse cada deployment y por qué difieren?
2. ¿Qué diferencia hay entre escalar **pods** (HPA) y saturar un **nodo**? ¿Qué alarma
   corresponde a cada uno?
3. ¿Qué problema resuelve la malla de servicios que ni el pipeline ni CloudWatch resuelven?
4. Regla del pipeline (ej. Snyk bloquea vulnerabilidades críticas) vs regla de la malla
   (ej. mTLS): ¿en qué momento del ciclo de vida actúa cada una?

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Alarma en `INSUFFICIENT_DATA` | Nadie ha publicado la métrica todavía | Ejecuta `bash push-metrica.sh` |
| `kubectl top` no muestra datos | Metrics Server recién instalado | Espera 2–5 min |
| El HPA no escala en la demo 2 | Carga insuficiente o pods ya al objetivo | Sube `WORKERS=12` o `DURACION=420` |
| La alarma de CPU del nodo no salta | El nodo t3.large reparte la carga; el objetivo didáctico es ver la tendencia | Es válido reportarlo como observación |
| `put-metric-data` / `put-metric-alarm` fallan | Permisos limitados de la sesión Academy | Las alarmas se omiten con aviso; la demo k8s sigue funcionando |
| Kiali no abre en el navegador | El contenedor no publicó el puerto | Levántalo con `-p 20001:20001` |

## Limpieza

```bash
bash limpiar-bloque06.sh   # borra alarmas + topic SNS (las métricas expiran solas)
```

Al finalizar la semana recuerda la limpieza general del laboratorio (`../aws-limpiar.sh`)
para no dejar recursos cobrables.
