# Headscale overlay — family-only access to Jellyfin & Emby

Jellyfin and Emby have **no public ingress**. Remote access is only over a
self-hosted [Headscale](https://headscale.net) tailnet that family devices
join with the stock Tailscale client, authenticating through Authentik. On the
LAN they stay reachable directly on the shared VIP `192.168.1.120`
(Jellyfin `:8097`, Emby `:8098`).

## Topology

```
family device (Tailscale client)
   │  control: register/coordinate (OIDC-gated by Authentik)
   ▼
headscale.reclyptor.com  ──(Cloudflare Tunnel)──►  headscale svc :8080
   │  data: WireGuard (direct p2p, else self-hosted DERP)
   ▼
playit.gg UDP  ──►  tailscale :41641  ──►  192.168.1.120:8097/8098
```

Four independent layers gate access; all must agree:

1. **Membership** — Headscale OIDC `allowed_groups: [media-family]`: only that
   Authentik group may enroll a device.
2. **Tailnet ACL** (`policy.hujson`) — `group:media-family` → only
   `192.168.1.120:8097,8098`.
3. **Router egress** (Cilium) — the router may forward only to `jellyfin:8096`
   and `emby:8096`, nothing else behind the VIP.
4. **App ingress** (Cilium) — Jellyfin/Emby accept from the router pod on
   `8096` only.

## One-time manual setup

The manifests carry placeholder secrets (`REPLACE_WITH_*`) and reference
Authentik objects that must be created in the UI. Do this **before** the
final `infra/kustomization.yaml` wiring is reconciled.

### 1. Authentik — group and providers

- Create group **`media-family`**; add each family user.
- **Headscale — OIDC provider + application**
  - Provider type OAuth2/OpenID, client type *Confidential*.
  - Redirect URI: `https://headscale.reclyptor.com/oidc/callback`
  - Set the **Client ID** to `headscale` (matches `configmap.yaml`).
  - Bind the application to the `media-family` group only.
  - Copy the **Client Secret** → `secrets/headscale-oidc-secret.yaml`
    (`oidc_client_secret`).
- **Jellyfin — OIDC provider + application**
  - Redirect URI: `https://<jellyfin-url>/sso/OID/redirect/authentik`
  - Bind to `media-family`. Note the Client ID/Secret for the plugin below.
- **Emby — LDAP provider + outpost**
  - Create an **LDAP provider**, bind it to `media-family`.
  - Create/assign an **LDAP outpost**; copy its **token** →
    `secrets/ldap-outpost-secret.yaml` (`token`). The outpost Deployment
    (`ldap-deployment.yaml`) runs it in-cluster.

### 2. Headscale — pre-auth key for the subnet router

After Headscale is running:

```sh
kubectl -n headscale exec sts/headscale -- \
  headscale preauthkeys create --user <admin-user> --reusable --expiration 87600h --tags tag:router
```

Put the key → `infra/tailscale/secrets/tailscale-authkey-secret.yaml`
(`authkey`). The router advertises `192.168.1.120/32`; the ACL
`autoApprovers` accepts it automatically because the key carries `tag:router`.

### 3. Jellyfin / Emby app config

- **Jellyfin**: install the **SSO-Auth** plugin, add an OpenID provider
  pointing at `https://authentik.reclyptor.com/application/o/jellyfin/` with the
  Client ID/Secret from step 1. Enable "role/group" gating on `media-family`.
- **Emby**: install the **LDAP** plugin, bind to
  `authentik-ldap.authentik.svc.cluster.local:389`, base DN
  `dc=ldap,dc=goauthentik,dc=io` (or as configured in the LDAP provider).

### 4. playit — data-path tunnels

In the playit dashboard, add tunnels forwarding to the in-cluster targets the
playit agent already reaches:

- **UDP** → `tailscale.tailscale.svc:41641` (WireGuard data path)
- **UDP** → `headscale.headscale.svc:3478` (DERP STUN)
- **TCP** → `headscale.headscale.svc:8080` (embedded DERP relay fallback)

### 5. Cloudflare — control plane hostname

Add a tunnel route: `headscale.reclyptor.com` →
`http://headscale.headscale.svc.cluster.local:8080`.

### 6. Encrypt and go live

```sh
sops -e -i infra/headscale/secrets/headscale-oidc-secret.yaml
sops -e -i infra/tailscale/secrets/tailscale-authkey-secret.yaml
sops -e -i infra/authentik/secrets/ldap-outpost-secret.yaml
```

`headscale`, `tailscale`, and the Authentik LDAP outpost are wired into
`infra/kustomization.yaml`; a push to `master` reconciles them.

## Client onboarding (per family device)

```sh
tailscale up --login-server https://headscale.reclyptor.com --accept-routes
```

The browser opens Authentik; a `media-family` member is approved automatically.
Jellyfin/Emby are then reachable at `192.168.1.120:8097` / `:8098` from
anywhere — same address as on the LAN.
