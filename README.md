# homelab

A single-node microk8s homelab: media/automation apps (Jellyfin, Sonarr,
Prowlarr, Bazarr, qBittorrent, Jellyseerr, FlareSolverr), Pi-hole, Immich, and
a Homepage dashboard — all packaged as one installable Helm chart at
[chart/homelab](chart/homelab).

Each app's API key/credentials are pushed to [Infisical](https://infisical.com)
by a post-install job, synced back into the cluster by the Infisical
Kubernetes Operator, and consumed by Homepage to auto-populate its dashboard
widgets. Enabling/disabling an app in `values.yaml` also adds/removes it from
the Homepage dashboard automatically. By default the chart deploys its own
Infisical instance and fully automates its setup too (project, machine
identity, API access) — see step 2 below.

## 1. Host bootstrap

Run once per node. This only handles things Helm can't (installing
microk8s/helm, enabling addons, netplan, host directories for hostPath
volumes):

```bash
./install.sh
microk8s config > ~/.kube/config   # let plain `helm`/`kubectl` talk to microk8s
```

If you're setting up wifi networking on the node, see [01-netcfg.yaml](01-netcfg.yaml)
(copy to `/etc/netplan/`, `chmod 600`, fill in SSID/password).

## 2. Configure secrets

Real credentials never belong in `values.yaml` (it's committed to git). Copy
the template below into an **untracked** file, e.g. `secrets.values.yaml`,
and fill it in.

### Self-hosted Infisical (default)

With `infisicalServer.enabled: true` (the default), the chart deploys its
*own* Infisical instance (app + bundled Postgres + Redis) and fully
automates everything that used to require clicking through Infisical's UI:
a post-install job bootstraps an admin account and organization, then a
second job creates a project, a machine identity with Universal Auth, and
grants it access — writing the resulting `clientId`/`clientSecret`/project
ID straight into the cluster. **You never need to open Infisical's UI or
manually create anything there.** The only thing you must provide is the
password for the admin account it creates for you:

```yaml
infisicalServerBootstrapAdmin:
  password: "<pick a real password>"

immich:
  postgres:
    password: "<pick a real password>"
  # Create this once via the Immich UI/CLI after first login (Settings > API Keys),
  # then re-run `helm upgrade` so the sync job can mint a scoped key for Homepage.
  adminApiKey: ""

qbittorrent:
  credentials:
    password: "<pick a real password>"

secretSync:
  jellyfin:
    adminUser: "<jellyfin admin username, once created>"
    adminPassword: "<jellyfin admin password>"
  pihole:
    webPasswordHash: ""

pihole:
  webPassword: "<pick a real password>"
```

If you're curious afterwards, the generated credentials are readable (once)
via:

```bash
kubectl -n homelab get secret infisical-credentials -o json \
  | jq -r '.data | map_values(@base64d)'
```

and the UI itself is reachable at `http://infisical.homelab/` (see
"LAN hostnames" below) using the admin email/password above
(`infisicalServerBootstrapAdmin.email`, default `admin@homelab.local`).

### Bring your own Infisical instead

If you already run Infisical elsewhere (self-hosted or Infisical Cloud) and
would rather point this cluster at it than have the chart deploy a new one,
set `infisicalServer.enabled: false` and fill in the values it would have
generated for you yourself:

```yaml
infisicalServer:
  enabled: false

infisical:
  hostAPI: "http://<your-infisical-service>.<namespace>.svc.cluster.local:8080"  # or https://app.infisical.com/api for Cloud
  projectId: "<your Infisical project ID>"
  clientId: "<machine identity client ID>"
  clientSecret: "<machine identity client secret>"
```

To get those three values, log in to your instance and:

1. **Project ID** — open (or create) the project you want this cluster to
   sync from, then Project Settings (gear icon, top left) → General →
   copy the **Project ID**. It's also the UUID in the URL:
   `.../project/<PROJECT_ID>/...`.
2. **Machine Identity (for `clientId`/`clientSecret`)** — Infisical
   authenticates *services*, not people, via Machine Identities:
   - Organization Settings → Access Control → **Identities** tab →
     **Create Identity**. Give it a name (e.g. `homelab-k8s`) and set
     Authentication Method to **Universal Auth**.
   - Open the identity you just created → **Authentication** tab. The
     **Client ID** is shown there; click **Create Client Secret** to
     generate the **Client Secret** — it's only ever shown once, so copy
     both into `secrets.values.yaml` immediately.
   - Back in your project: Project Access Control → **Machine Identities**
     tab → **Add Identity** → pick the identity you created → give it a
     role that can read/write secrets (e.g. Admin, or a custom role) for
     the environment named in `infisical.environmentSlug` (default
     `prod`) and secret path `/`. Without this step, authentication will
     succeed but every secret push/read from the sync job will be denied.

The rest of the `secrets.values.yaml` template above (`immich.postgres`,
`qbittorrent.credentials`, `secretSync.*`, `pihole.webPassword`) is the same
either way.

## 3. Install

```bash
helm dependency update ./chart/homelab
helm install homelab ./chart/homelab \
  -n homelab --create-namespace \
  -f secrets.values.yaml
```

This installs, in order:
1. The Infisical Kubernetes Operator and (if `infisicalServer.enabled`) a
   self-hosted Infisical instance — both chart dependencies.
2. All enabled apps.
3. A handful of post-install hook jobs, in sequence:
   - (self-hosted mode only) Infisical's own bootstrap job creates an admin
     user/org, then this chart's `infisical-provision` job creates a
     project, machine identity, and grants it access.
   - `secret-sync` waits for each app to generate its config, reads out its
     API key (or, for Jellyfin/Immich, calls their API to mint one), and
     pushes those keys to Infisical.
4. The Infisical Operator syncs those keys into the `homepage-api-keys`
   Secret, which Homepage reads via `envFrom` to populate its widgets.

See `helm install`'s NOTES output for the URLs of everything that got
enabled. Give it a few minutes on first install in self-hosted mode — Infisical
itself has to come up (Postgres + Redis + the app) before anything downstream
can run, and Homepage's widgets only populate once the Operator's first
resync completes after that.

## LAN hostnames

By default (`global.lanIngress.enabled: true`) every app also gets an
`Ingress` at `<app>.homelab` (e.g. `immich.homelab`, `sonarr.homelab`) —
see the base domain at `global.lanIngress.baseDomain`. This is on top of,
not instead of, the NodePort URLs; both work.

That hostname only resolves for a browser once **something on your LAN
answers DNS for it and points it at the node's IP**
(`global.nodeIP`) — the same distinction as `ssh homelab` only working
because it's in your `~/.ssh/config`, not because any name server
knows about it. The chart does not configure this for you. Two ways to
set it up, using the Pi-hole this stack already installs:

1. **Wildcard (recommended, one-time setup):** Pi-hole → Settings → DNS →
   the box under "Custom DNS records", or by mounting a
   `/etc/dnsmasq.d/*.conf` file into the pihole container with:
   ```
   address=/homelab/192.168.78.166
   ```
   This resolves `*.homelab` (any app, present or future) to the node.
   Confirm your Pi-hole version still honors dnsmasq-style config drop-ins
   before relying on it — check Settings → DNS in its admin UI.
2. **Per-app records:** Pi-hole admin UI → Local DNS Records → add
   `immich.homelab` → `192.168.78.166`, one entry per app. More manual,
   but guaranteed to work regardless of Pi-hole version.

Either way, **your LAN clients need to actually use Pi-hole as their DNS
server** for this to work without per-device config — set your router's
DHCP "DNS server" option to the node's IP, or point each device's network
settings at it manually. If you don't want to do that, add the same
`<app>.homelab` → node IP mapping to each client's `/etc/hosts` (or
Windows' `C:\Windows\System32\drivers\etc\hosts`) instead — same effect,
just per-device rather than LAN-wide.

If neither DNS piece is set up yet, disable this and stick to NodePort URLs:

```bash
helm upgrade homelab ./chart/homelab -n homelab -f secrets.values.yaml \
  --set global.lanIngress.enabled=false
```

## Toggling apps

Every app has an `<app>.enabled` flag in
[chart/homelab/values.yaml](chart/homelab/values.yaml). Disabling one removes
its manifests **and** its entry on the Homepage dashboard on the next
`helm upgrade`:

```bash
helm upgrade homelab ./chart/homelab -n homelab -f secrets.values.yaml \
  --set jellyseerr.enabled=false
```

## Upgrading / re-syncing secrets

`helm upgrade` re-runs the secret-sync job and the qBittorrent WebUI fix job
(both are `post-install,post-upgrade` hooks), so re-running keys or
credential rotation just means:

```bash
helm upgrade homelab ./chart/homelab -n homelab -f secrets.values.yaml
```

## Troubleshooting

- `kubectl -n homelab logs job/secret-sync` — see what got pushed to
  Infisical (or why something didn't).
- `kubectl -n homelab get infisicalsecret` — check the Operator's sync
  status for the `homepage-api-keys` Secret.
- Self-hosted Infisical mode (`infisicalServer.enabled: true`) only:
  - `kubectl -n homelab get jobs | grep bootstrap` to find its name, then
    `kubectl -n homelab logs job/<that name>` — Infisical's own admin/org
    bootstrap job (named `<release>-bootstrap-<revision>`, so it changes
    on every `helm upgrade`). If this fails, `infisical-provision` never
    gets a token to work with.
  - `kubectl -n homelab logs job/infisical-provision` — this chart's
    project/machine-identity setup job. Safe to re-run (`helm upgrade`
    re-triggers it) — it exits immediately once `infisical-credentials`
    is populated.
  - `kubectl -n homelab get pods -l app=infisical-server` /
    `kubectl -n homelab logs deploy/infisical-server` — the Infisical app
    itself; check this if the bootstrap job's `wait-for-infisical`
    initContainer never succeeds.
- If the very first `helm install` fails because the `InfisicalSecret` CRD
  isn't registered yet, install just the operator (and, in self-hosted
  mode, the Infisical server) first
  (`--set homepage.enabled=false --set secretSync.enabled=false`), then
  `helm upgrade` with everything enabled.
