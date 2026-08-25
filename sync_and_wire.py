import os
import xml.etree.ElementTree as ET
import yaml
import requests
from infisical_client import InfisicalClient, ClientSettings

# 1. Initialize Infisical SDK
client = InfisicalClient(
    ClientSettings(
        auth_mode="machine-identity",
        client_id=os.environ["INFISICAL_CLIENT_ID"],
        client_secret=os.environ["INFISICAL_CLIENT_SECRET"],
    )
)
PROJECT_ID = os.environ["INFISICAL_PROJECT_ID"]
ENV_SLUG = "prod"

def upsert_secret(key, value):
    """Pushes or updates a secret in Infisical."""
    if not value:
        return
    try:
        client.secrets.create_secret(
            secret_name=key,
            secret_value=value,
            project_id=PROJECT_ID,
            environment_slug=ENV_SLUG,
            secret_path="/"
        )
        print(f"[Infisical] Synced {key}")
    except Exception:
        # Secret exists; trigger update
        client.secrets.update_secret(
            secret_name=key,
            secret_value=value,
            project_id=PROJECT_ID,
            environment_slug=ENV_SLUG,
            secret_path="/"
        )
        print(f"[Infisical] Updated {key}")

# --- A. Extract Local File-Based Keys ---
def get_xml_key(path):
    try:
        return ET.parse(path).getroot().find("ApiKey").text
    except: return None

def get_bazarr_key(path):
    try:
        with open(path) as f:
            return yaml.safe_load(f).get('analytics', {}).get('apikey')
    except: return None

secrets_manifest = {
    "SONARR_API_KEY": get_xml_key("/pvc-mounts/sonarr/config.xml"),
    "PROWLARR_API_KEY": get_xml_key("/pvc-mounts/prowlarr/config.xml"),
    "BAZARR_API_KEY": get_bazarr_key("/pvc-mounts/bazarr/config.yaml"),
    "QBITTORRENT_USER": os.getenv("QBIT_USER", "admin"),
    "QBITTORRENT_PASS": os.getenv("QBIT_PASS", "adminadmin"),
    "PIHOLE_API_KEY": os.getenv("PIHOLE_WEBPASSWORD_HASH")
}

# --- B. Programmatically Generate Jellyfin API Key ---
try:
    auth_resp = requests.post(
        "http://jellyfin-service.default.svc.cluster.local:8096/Users/AuthenticateByName",
        json={"Username": os.environ["JELLYFIN_ADMIN_USER"], "Pw": os.environ["JELLYFIN_ADMIN_PASS"]},
        headers={"X-Emby-Authorization": 'MediaBrowser Client="SyncScript", Device="K8s", DeviceId="1", Version="1.0"'}
    ).json()
    token = auth_resp["AccessToken"]
    
    # Generate dedicated API key for Homepage
    key_resp = requests.post(
        "http://jellyfin-service.default.svc.cluster.local:8096/Auth/Keys?app=Homepage",
        headers={"X-Emby-Token": token}
    ).json()
    secrets_manifest["JELLYFIN_API_KEY"] = key_resp.get("AccessToken")
except Exception as e:
    print(f"[Jellyfin Key Gen Error]: {e}")

# --- C. Programmatically Generate Immich API Key ---
try:
    immich_key_resp = requests.post(
        "http://immich-service.default.svc.cluster.local:2283/api/api-key",
        headers={"x-api-key": os.environ["IMMICH_ADMIN_KEY"]},
        json={"name": "Homepage Dashboard Key"}
    ).json()
    secrets_manifest["IMMICH_API_KEY"] = immich_key_resp.get("secret")
except Exception as e:
    print(f"[Immich Key Gen Error]: {e}")

# --- D. Push All Secrets to Infisical ---
for k, v in secrets_manifest.items():
    upsert_secret(k, v)