# Kubernetes

GitOps manifests for the homelab cluster, reconciled by [Flux](https://fluxcd.io)
from this repository's `master` branch.

## Layout

```
flux-system/   Flux components, GitRepository/Kustomization sync objects, layer definitions
core/          Cluster plumbing: Cilium policies, CoreDNS, NodeLocal DNSCache, GPU, storage
infra/         Shared services: databases, queues, auth, tunnels, object storage
apps/          End-user applications
secrets/       Bootstrap-only secrets (applied by bootstrap.sh, not reconciled by Flux)
```

Every app/service directory is self-contained: `namespace.yaml`,
`kustomization.yaml`, workload, `service.yaml`, `ciliumnetworkpolicy.yaml`,
and a `secrets/` subdirectory with SOPS-encrypted secrets where needed.

`CLAUDE.md` contains agent directives, not cluster documentation.

## Reconciliation

Flux reconciles the repo as four layered Kustomizations (`flux-system/layers.yaml`):

```
flux-system (path ./flux-system)
└── core    (path ./core, health-gated on CoreDNS, NodeLocal DNS, and all HelmReleases)
    └── infra (path ./infra, dependsOn core)
        └── apps (path ./apps, dependsOn infra)
```

Only `core` is health-gated: StorageClasses, the NVIDIA RuntimeClass, and DNS
are guaranteed Ready before `infra`/`apps` apply, but an unhealthy database in
`infra` never blocks reconciliation of `apps`.

## Bootstrap

On a fresh cluster, `./bootstrap.sh`:

1. creates the `flux-system` namespace
2. decrypts and applies everything in `secrets/` (requires the YubiKey age identity)
3. applies the Flux components and sync objects, then reconciles

After that, everything is driven by git pushes to `master`.

## Secrets

All secrets are committed SOPS-encrypted with [age](https://age-encryption.org)
(`.sops.yaml`). There are two recipients:

- the operator's YubiKey identity (offline, used at bootstrap)
- the cluster's own age key, whose private half lives in
  `secrets/sops-age-secret.yaml` — itself encrypted to the YubiKey, which is
  what breaks the chicken-and-egg: the operator decrypts it once at bootstrap,
  and Flux's kustomize-controller uses it for everything thereafter.

## Networking

- **Cilium is installed out-of-band** (not managed by this repo): native
  routing + WireGuard, all-wired dataplane. This repo only carries its
  policies, the LB-IPAM pool (`192.168.1.120/29`), and the L2 announcement
  policy. Do not add a tunnel/VXLAN config — it breaks WireGuard MTU.
- **Zero-trust**: `core/cilium/baseline-network-policy.yaml` default-denies
  every namespace except `kube-system`/`flux-system`, allowing only kubelet
  probes in and L4 DNS out. Each workload carries its own
  CiliumNetworkPolicy for everything else.
- **LoadBalancer services share `192.168.1.120`** via the
  `lbipam.cilium.io/sharing-key: lan-shared` annotation trio, announced over L2.
- **HTTP ingress goes through Cloudflare Tunnels** (`infra/cloudflare`) —
  there is deliberately no ingress controller, cert-manager, or Gateway API.
  Game/UDP traffic ingresses via playit.gg (`infra/playit`).
- **CoreDNS** (`core/coredns`) is a hand-maintained replacement of the
  distro's deployment (2 replicas + pod anti-affinity for HA). Its image and
  pod spec must be kept in sync with cluster upgrades manually.
- **NodeLocal DNSCache** (`core/node-local-dns`) is required for Cilium
  `toFQDNs` policies to work with WireGuard — do not remove it while any
  policy uses FQDN rules.

## Storage

- **democratic-csi** provisions iSCSI volumes from three TrueNAS appliances
  (`dxp4800`, `dxp6800`, `fs6712x`). Dynamic PVCs use
  `iscsi-persistent-fs6712x`; the dxp4800/dxp6800 drivers currently exist for
  their VolumeSnapshotClasses (backup platform).
- **Static NFS PVs** (media/download shares) use placeholder `1Mi` capacities
  and explicit `volumeName` binding; the `nfs-*` storageClassName values are
  matching labels, not real StorageClasses.
- **snapshot-controller + VolSync** back the in-progress backup platform
  (CSI snapshots + restic to MinIO).

## Conventions

- Images ride `:latest` (factorio: `:stable`) with `imagePullPolicy: Always`;
  pinned tags use `IfNotPresent`.
- Same-kind resources for one app live in a single file separated by `---`.
- `apps/makemkv` fans out to eight per-drive instances: each stub in
  `deployment.yaml`/`service.yaml`/`pvc.yaml` carries only per-drive facts,
  and the shared spec lives in `*-patch.yaml`, applied by name pattern from
  its `kustomization.yaml`.
- Workloads with persistent volumes are StatefulSets; stateless ones are
  Deployments (singleton agents that must never run twice use
  `strategy: Recreate`).
