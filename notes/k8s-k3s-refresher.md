# Kubernetes & k3s Reference

Reference documentation for the Kubernetes concepts used in Inception-of-Things. Covers
the declarative model, cluster architecture, core objects, networking, k3s, and k3d, with
diagrams for each topic and review questions at the end.

## Contents

1. [Concept map](#1-concept-map)
2. [The declarative model](#2-the-declarative-model)
3. [Cluster architecture](#3-cluster-architecture)
4. [Core objects](#4-core-objects)
5. [Request flow](#5-request-flow)
6. [k3s](#6-k3s)
7. [k3d](#7-k3d)
8. [Project mapping](#8-project-mapping)
9. [Review questions](#9-review-questions)
10. [Glossary](#10-glossary)

## 1. Concept map

Overview of every topic in this document and how they relate.

```
                                 KUBERNETES (k8s)
                      "keep my containers running, as declared"
                                       |
        -------------------------------+-------------------------------
        |                      |                   |                   |
   DECLARATIVE           THE CLUSTER          THE OBJECTS          NETWORKING
   desired state      ---------------       --------------       --------------
   is declared; a     CONTROL PLANE          Pod                 Pod gets an IP
   loop reconciles    (decides)              ReplicaSet          Service = stable
   it continuously     - API server          Deployment            address + balancer
        |              - etcd                 Service             Ingress = HTTP entry
   "I want 3"          - scheduler            Ingress                   |
        |              - controllers          Namespace           client -> Ingress
   loop keeps          WORKER NODES           ConfigMap/Secret      -> Service -> Pod
   it at 3             (execute)              Volume
                        - kubelet
                        - runtime
                        - kube-proxy
                                       |
                                     k3s
                     certified Kubernetes packaged as one binary
                     server/agent roles, SQLite, bundled add-ons
                                       |
                                     k3d
                     k3s clusters running inside Docker (p3)
```

## 2. The declarative model

Kubernetes is an orchestrator: it runs and manages containers across one or more
machines. It is declarative. The user does not issue step-by-step instructions; the user
submits a description of the desired end state, and Kubernetes works continuously to make
the actual state match it.

This is performed by controllers, each running a reconciliation loop:

```
     DESIRED STATE                 RECONCILIATION LOOP (runs continuously)
   +---------------+          +--------------------------------------+
   | replicas: 3   |          |  1. read desired state      (3)      |
   |               |  ---->   |  2. read actual state       (2)      |
   +---------------+          |  3. if different, act  -> create 1   |
                              |  4. repeat                           |
                              +--------------------------------------+
```

Consequence: if a managed Pod is deleted manually, the controller detects that the actual
count no longer matches the desired count and creates a replacement.

Analogy: a thermostat. A target temperature is set, and the device continuously senses
and corrects toward it. Kubernetes applies the same principle to containers.

## 3. Cluster architecture

A cluster is a set of machines (nodes) with two roles: the control plane, which makes
decisions and stores state, and worker nodes, which run workloads.

```
                              CLUSTER
   =====================================================================
   |                 CONTROL PLANE  (decides, stores state)             |
   |                                                                    |
   |   [API server] ...... single entry point; all components and       |
   |        |              kubectl communicate through it                |
   |   [etcd] ............ key-value store holding all cluster state     |
   |   [scheduler] ....... assigns each new Pod to a node                |
   |   [controllers] ..... run the reconciliation loops                  |
   =====================================================================
                 |                               |
                 v                               v
   ============================     ============================
   |  WORKER NODE (executes)  |     |  WORKER NODE (executes)  |
   |                          |     |                          |
   |  [kubelet]               |     |  [kubelet]               |
   |  [container runtime]     |     |  [container runtime]     |
   |  [kube-proxy]            |     |  [kube-proxy]            |
   |   Pod  Pod  Pod          |     |   Pod  Pod               |
   ============================     ============================
```

Control plane components:

- API server: the only entry point to the cluster. It validates requests and is the only
  component that reads and writes the datastore. If it is unavailable, no changes can be
  made.
- etcd: a key-value database holding the full cluster state (desired and current). k3s
  uses SQLite by default instead ([section 6](#6-k3s)).
- Scheduler: selects a node for each new Pod based on available resources and
  constraints.
- Controller manager: runs the reconciliation loops, such as the Deployment controller
  that maintains the requested replica count.

Worker node components:

- kubelet: the node agent. It receives Pod assignments from the API server, has the
  runtime start them, and reports their status.
- Container runtime: runs the containers (containerd in k3s).
- kube-proxy: configures node networking so traffic reaches Services.

Mnemonic for the control plane: "A Smart Scheduler Controls" — API server, Storage
(etcd), Scheduler, Controllers.

Project note: in p1 the server VM runs the control plane and the worker VM runs workloads
only. The worker joins the server to form a single cluster.

## 4. Core objects

Objects describe the desired state and are usually written in YAML. The main objects
nest as follows:

```
        INGRESS           HTTP entry point; routes by host/path
           |
        SERVICE           stable virtual IP + DNS name; load-balances
           |  (selects Pods by label)
        DEPLOYMENT        maintains N replicas; performs rolling updates
           |
        REPLICASET        guarantees the replica count
           |
     +-----+-----+
     |     |     |
    POD   POD   POD       running container(s); IP changes on recreation
```

Summary: an Ingress routes external traffic to a Service, the Service distributes it
across Pods, and a Deployment (through a ReplicaSet) keeps the correct number of those
Pods running.

Mnemonic, bottom to top: "Please Deploy Reliable Services Inside" — Pod, Deployment,
ReplicaSet, Service, Ingress.

### Pod

The smallest deployable unit: one container, or several that must run together, sharing
one IP address. A standalone Pod is not restarted if it fails, so Pods are normally
managed by a higher-level object rather than created directly.

```yaml
apiVersion: v1
kind: Pod
metadata: { name: hello }
spec:
  containers:
    - name: web
      image: nginx
```

### ReplicaSet

Maintains a fixed number of identical Pods. Normally created and managed by a Deployment
rather than written directly.

### Deployment

The standard object for running a stateless application. It specifies an image and a
replica count, manages a ReplicaSet, replaces failed Pods, and performs rolling updates
(replacing Pods incrementally to avoid downtime). The p2 requirement of three replicas
for one application corresponds to `replicas: 3`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: app2 }
spec:
  replicas: 3                       # maintain 3 Pods
  selector: { matchLabels: { app: app2 } }
  template:                         # Pod template used for each replica
    metadata: { labels: { app: app2 } }
    spec:
      containers:
        - name: web
          image: myregistry/app2:1.0
```

### Service

Provides a stable virtual IP and DNS name for a set of Pods. Pod IPs change whenever Pods
are recreated, so clients address the Service instead, which load-balances across the
currently running Pods. Pods are selected by label; `app: app2` below matches the
Deployment above.

```yaml
apiVersion: v1
kind: Service
metadata: { name: app2 }
spec:
  selector: { app: app2 }
  ports: [ { port: 80, targetPort: 80 } ]
```

### Ingress

Defines HTTP routing from outside the cluster to Services, by hostname or path. The
Ingress object holds only the rules; an ingress controller enforces them (Traefik, bundled
with k3s). This is the central mechanism of p2.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: apps }
spec:
  rules:
    - host: app1.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: app1, port: { number: 80 } } }
```

### Other objects

- Namespace: a logical partition within a cluster for grouping and isolating objects. p3
  uses `argocd` and `dev`.
- ConfigMap / Secret: supply configuration and sensitive values to Pods without embedding
  them in the image.
- Volume / PersistentVolume: storage that persists beyond a container's lifetime.

### kubectl

`kubectl` is the command-line client for the API server.

```bash
kubectl get nodes                  # list cluster nodes
kubectl get pods -A                # list Pods in all namespaces
kubectl get deploy,svc,ingress     # list these object types
kubectl apply -f app.yaml          # create or update objects from a file
kubectl delete -f app.yaml         # delete objects defined in a file
kubectl describe pod <name>        # detailed status and events
kubectl logs <pod>                 # container logs (-f to follow)
kubectl exec -it <pod> -- sh       # shell inside a container
kubectl get all -n <namespace>     # all objects in a namespace
```

`kubectl apply -f` is the declarative workflow: manifests are kept in files, edited, and
re-applied; applying an unchanged file has no effect. In k3s, manifests placed in
`/var/lib/rancher/k3s/server/manifests/` are applied automatically at startup.

Troubleshooting order: `get pods` (state) → `describe pod` (events) → `logs` (application
output).

## 5. Request flow

External HTTP traffic passes through three layers:

```
   CLIENT
   (request for http://app1.com)
        |
        v
   [ INGRESS ]          matches host "app1.com" to a rule
        |               (enforced by the ingress controller, Traefik)
        v
   [ SERVICE app1 ]     stable virtual IP; selects a healthy Pod
        |
        v
   [ POD ] [ POD ] [ POD ]     one Pod handles the request

   Pod network: every Pod has its own IP and can reach every other Pod,
   including across nodes. Provided by the CNI plugin (flannel in k3s).
   Service names resolve through cluster DNS (CoreDNS).
```

Chain to remember: Ingress → Service → Pod. This diagram is the full p2 design.

## 6. k3s

k3s is a certified, lightweight Kubernetes distribution. It exposes the same API, objects,
and kubectl behavior as standard Kubernetes, packaged for low resource use. This is why
the subject can require only 1 CPU and 512–1024 MB of RAM.

```
   STANDARD k8s                          k3s
   ------------------------------        ----------------------------------
   many separate components              single binary (~50-70 MB),
   (kubeadm, etcd, CNI, ...)             one systemd service
                                         install: curl -sfL https://get.k3s.io | sh
   etcd                                  SQLite by default (etcd optional)
   add-ons installed separately          bundled: containerd, flannel, CoreDNS,
                                         Traefik, ServiceLB, local-path storage
```

Because Traefik is bundled, Ingress objects work in k3s without installing a controller.

### Server and agent roles

```
   [ k3s SERVER ]   runs the control plane; generates the node token
          ^
          |  joins with:  K3S_URL=https://<server-ip>:6443  +  K3S_TOKEN
          |
   [ k3s AGENT ]    runs workloads only
```

A server node runs the control plane and can also run workloads. An agent node runs
workloads only and joins a server using the server URL and the node token. This
corresponds directly to p1's server and worker.

See also: [p1 Notes: 7. Forming the cluster](p1-notes.md#7-forming-the-cluster).

### Differences from standard Kubernetes

- Usage: objects, YAML, and kubectl are identical; knowledge transfers directly.
- Installation: one command and one service, versus multiple components.
- Datastore: SQLite by default, versus etcd.
- Add-ons: networking, DNS, ingress, and storage are preinstalled.

## 7. k3d

k3d runs k3s clusters inside Docker containers, with each node as a container. Clusters
can be created and removed in seconds without a VM; Docker is required. p3 combines k3d
with Argo CD for GitOps: Argo CD watches a GitHub repository and deploys its manifests
automatically, making the repository the source of truth.

Distinction: k3s is the Kubernetes distribution; k3d is a tool that runs k3s inside
Docker.

## 8. Project mapping

```
   p1  ->  k3s on 2 VMs: server (control plane) + agent (workloads)
                 |
   p2  ->  1 k3s server, 3 apps behind one Ingress routed by host
           (app1.com / app2.com / default app3); app2 uses replicas: 3
                 |
   p3  ->  k3d cluster + Argo CD (GitOps from GitHub)
           namespaces: argocd, dev
```

See also: [p1 Notes: 1. Overview](p1-notes.md#1-overview).

## 9. Review questions

1. What does "declarative" mean in Kubernetes? — The desired end state is declared, and
   reconciliation loops keep the actual state matching it.
2. Which components form the control plane, and which run on each worker node? —
   Control plane: API server, etcd, scheduler, controllers. Node: kubelet, container
   runtime, kube-proxy.
3. Why do clients use a Service instead of a Pod IP? — Pod IPs change on recreation; a
   Service provides a stable address and load-balancing.
4. What is the path of an external HTTP request? — Ingress → Service → Pod.
5. How do k3s server and agent nodes differ? — The server runs the control plane and
   issues the token; the agent runs workloads and joins with the server URL and token.
6. How do k3s and k3d differ? — k3s is a Kubernetes distribution; k3d runs k3s inside
   Docker.

## 10. Glossary

- Cluster: the set of machines running Kubernetes together.
- Node: a single machine in the cluster.
- Control plane: the components that make decisions and store cluster state.
- Pod: the smallest deployable unit; one or more containers sharing a network identity.
- ReplicaSet: maintains a fixed number of identical Pods.
- Deployment: manages ReplicaSets and rolling updates for stateless applications.
- Service: a stable IP and DNS name with load-balancing for a set of Pods.
- Ingress: HTTP routing into the cluster by host or path.
- Ingress controller: the component that enforces Ingress rules (Traefik in k3s).
- Namespace: a logical partition within a cluster.
- CNI: the plugin that provides Pod networking (flannel in k3s).
- kubelet: the per-node agent that runs and monitors Pods.
- Reconciliation loop: a controller process driving actual state toward desired state.
- Manifest: a YAML file describing one or more objects.
- Declarative: describing the desired end state rather than the steps to reach it.
