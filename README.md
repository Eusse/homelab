# homelab

A single-node microk8s homelab: media/automation apps (Jellyfin, Sonarr,
Prowlarr, Bazarr, qBittorrent, Jellyseerr, FlareSolverr), Pi-hole, Immich, and
a Homepage dashboard — all packaged as one installable Helm chart at
[chart/homelab](chart/homelab).

Each app's API key/credentials are pushed to [Infisical](https://infisical.com)
by a post-install job, synced back into the cluster by the Infisical
Kubernetes Operator, and consumed by Homepage to auto-populate its dashboard
widgets. Enabling/disabling an app in `values.yaml` also adds/removes it from
the Homepage dashboard automatically.

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
and fill it in:

```yaml
infisical:
  projectId: "<your Infisical project ID>"
  clientId: "<machine identity client ID>"
  clientSecret: "<machine identity client secret>"

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

The Infisical `clientId`/`clientSecret` are a **Machine Identity** with
Universal Auth configured in your Infisical project, scoped to that project.

## 3. Install

```bash
helm dependency update ./chart/homelab
helm install homelab ./chart/homelab \
  -n homelab --create-namespace \
  -f secrets.values.yaml
```

This installs the Infisical Kubernetes Operator (as a chart dependency), all
enabled apps, and runs a post-install job that:
1. Waits for each app to generate its config, reads out its API key (or, for
   Jellyfin/Immich, calls their API to mint one).
2. Pushes those keys to Infisical.
3. The Infisical Operator syncs them into the `homepage-api-keys` Secret,
   which Homepage reads via `envFrom` to populate its widgets.

See `helm install`'s NOTES output for the URLs of everything that got
enabled. Give it a minute after first install — Homepage's widgets only
populate once the Infisical Operator's first resync completes.

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
- If the very first `helm install` fails because the `InfisicalSecret` CRD
  isn't registered yet, install just the operator first
  (`--set homepage.enabled=false --set secretSync.enabled=false`), then
  `helm upgrade` with everything enabled.
