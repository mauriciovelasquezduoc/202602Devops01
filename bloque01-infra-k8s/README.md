# Bloque 01 - Infraestructura K8s

Este bloque consolida la preparacion de infraestructura de `guia-03` bloques 1, 2 y 3 para llegar rapidamente a un entorno Kubernetes listo en AWS.

El script principal es:

```bash
bash ejecutar.sh
```

El script es idempotente: si la VPC, el cluster EKS, el NodeGroup o los addons ya existen, valida su estado y continua. Si faltan, los crea usando los templates locales incluidos en `templates/`.

## Que prepara

- VPC Multi-AZ `laboratorio-ep03` con subnets publicas, privadas de aplicacion y privadas de datos.
- VPC Endpoints para servicios requeridos por EKS/ECR/CloudWatch.
- Cluster EKS `laboratorio-ep03-eks`.
- Addons EKS: `vpc-cni`, `coredns`, `kube-proxy` y `metrics-server`.
- NodeGroup SPOT `laboratorio-ep03-nodegroup` en subnets privadas de aplicacion.
- Kubeconfig local apuntando al cluster.
- Validacion de nodos, pods de sistema, Metrics Server y CloudWatch logs.
- Reporte Markdown en `reports/` con resumen y comandos de evidencia.

## Diagrama

```mermaid
flowchart TB
    User[Operador / ejecutar.sh] --> AWS[AWS Account us-east-1]

    subgraph VPC[VPC laboratorio-ep03 10.0.0.0/16]
        IGW[Internet Gateway]

        subgraph Public[Subnets publicas]
            PubA[public-subnet-a us-east-1a]
            PubB[public-subnet-b us-east-1b]
        end

        subgraph PrivateApp[Subnets privadas app]
            AppA[private-app-a us-east-1a]
            AppB[private-app-b us-east-1b]
        end

        subgraph PrivateData[Subnets privadas data]
            DataA[private-data-a us-east-1a]
            DataB[private-data-b us-east-1b]
        end

        Endpoints[VPC Endpoints: S3, ECR API, ECR DKR, STS, Logs, EC2, EKS, ELB]
    end

    AWS --> VPC
    Public --> IGW
    PrivateApp --> Endpoints
    PrivateData --> Endpoints

    subgraph EKS[EKS laboratorio-ep03-eks]
        ControlPlane[Control Plane EKS]
        Addons[Addons: vpc-cni, coredns, kube-proxy, metrics-server]
        NodeGroup[NodeGroup SPOT laboratorio-ep03-nodegroup]
        Nodes[Worker nodes t3.large]
    end

    VPC --> EKS
    ControlPlane --> Addons
    NodeGroup --> Nodes
    Nodes --> PrivateApp

    EKS --> CW[CloudWatch Logs]
    EKS --> Kubectl[kubectl / kubeconfig local]
```

## Variables utiles

Puedes sobreescribir valores por variable de entorno:

```bash
REGION=us-east-1 \
VPC_STACK=laboratorio-ep03-vpc \
EKS_STACK=laboratorio-ep03-eks \
CLUSTER_NAME=laboratorio-ep03-eks \
NODEGROUP_NAME=laboratorio-ep03-nodegroup \
bash ejecutar.sh
```

## Archivos locales usados

- `templates/vpc.yaml`: template CloudFormation de VPC copiado desde guia-03.
- `templates/fase_4_cluster_eks.yaml`: template CloudFormation de EKS copiado desde guia-03.
- `../secrets.txt`: credenciales/variables de laboratorio ubicadas en la raiz de `guia-04`, si existe.

## Salida esperada

Al finalizar deberias ver:

- Stack VPC en estado `CREATE_COMPLETE` o `UPDATE_COMPLETE`.
- Stack EKS en estado `CREATE_COMPLETE` o `UPDATE_COMPLETE`.
- Cluster EKS `ACTIVE`.
- NodeGroup `ACTIVE`.
- Nodos Kubernetes en estado `Ready`.
- Pods de `kube-system` visibles.
- Reporte generado en `reports/infra-k8s-YYYYMMDD-HHMMSS.md`.

## Comandos de verificacion

```bash
aws eks describe-cluster --region us-east-1 --name laboratorio-ep03-eks --query 'cluster.{name:name,status:status,version:version}' --output table
aws eks describe-nodegroup --region us-east-1 --cluster-name laboratorio-ep03-eks --nodegroup-name laboratorio-ep03-nodegroup --query 'nodegroup.{name:nodegroupName,status:status,capacity:capacityType}' --output table
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
kubectl top nodes
```
