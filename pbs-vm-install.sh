#!/usr/bin/env bash
# Proxmox Backup Server as VM - one-liner installer (runs on PVE host)
# Repo: https://github.com/HatchetMan111/ProxmoxBackUpServerVM
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ProxmoxBackUpServerVM/main/pbs-vm-install.sh)"
#   bash pbs-vm-install.sh --unattended --dry-run
set -euo pipefail

VM_NAME="${VM_NAME:-pbs}"
VMID="${VMID:-auto}"
CORES="${CORES:-2}"
MEMORY="${MEMORY:-4096}"
OS_DISK_SIZE="${OS_DISK_SIZE:-32}"
DATA_DISK_SIZE="${DATA_DISK_SIZE:-0}"
BRIDGE="${BRIDGE:-auto}"
IMG_STORAGE="${IMG_STORAGE:-auto}"
ISO_STORAGE="${ISO_STORAGE:-auto}"
ISO_URL="${ISO_URL:-auto}"
MODE="manual"
DRY_RUN=0
CPU_TYPE="${CPU_TYPE:-host}"

log() { echo "[pbs-vm] $*"; }
die() { echo "[pbs-vm][ERROR] $*" >&2; exit 1; }
run() { if [ "$DRY_RUN" -eq 1 ]; then echo "+ $*"; else eval "$@"; fi; }

usage() {
  cat <<EOF
PBS-VM Installer (auf PVE-Host als root ausfuehren)

Optionen:
  --vmid ID            VMID (default: auto = naechste freie via pvesh)
  --name NAME          VM-Name (default: pbs)
  --cores N            CPU-Kerne (default: 2)
  --memory MB          RAM in MB (default: 4096)
  --os-disk SIZE       OS-Disk, z.B. 32G (default: 32)
  --data-disk SIZE     extra Datastore-Disk in G, 0 = keine (default: 0)
  --bridge BR          z.B. vmbr0 (default: auto)
  --storage ST         Storage fuer VM-Disks (default: auto)
  --iso-storage ST     Storage fuer ISO (default: auto)
  --iso-url URL        PBS-ISO URL (default: auto = neueste von enterprise.proxmox.com)
  --unattended         vollautomatische ISO-Installation per answer.toml (PBS >= 3.1)
  --manual             nur VM erstellen + ISO einlegen, Installer manuell klicken (default)
  --dry-run            nur zeigen, nichts erstellen
  -h, --help           Hilfe
Env-Variablen mit gleichen Namen werden ebenfalls gelesen.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vmid) VMID="$2"; shift 2;;
    --name) VM_NAME="$2"; shift 2;;
    --cores) CORES="$2"; shift 2;;
    --memory) MEMORY="$2"; shift 2;;
    --os-disk) OS_DISK_SIZE="$2"; shift 2;;
    --data-disk) DATA_DISK_SIZE="$2"; shift 2;;
    --bridge) BRIDGE="$2"; shift 2;;
    --storage) IMG_STORAGE="$2"; shift 2;;
    --iso-storage) ISO_STORAGE="$2"; shift 2;;
    --iso-url) ISO_URL="$2"; shift 2;;
    --unattended) MODE="unattended"; shift;;
    --manual) MODE="manual"; shift;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unbekannte Option: $1 (siehe --help)";;
  esac
done

# Groessen normalisieren (erlaube "32" oder "32G")
norm_g() { local v="$1"; if [[ "$v" =~ ^[0-9]+$ ]]; then echo "${v}G"; else echo "$v"; fi; }
OS_DISK_SIZE="$(norm_g "$OS_DISK_SIZE")"

[ "$(id -u)" -eq 0 ] || die "Bitte als root auf dem PVE-Host ausfuehren."
command -v qm >/dev/null || die "qm nicht gefunden - laeuft das wirklich auf einem Proxmox VE Host?"
command -v pvesm >/dev/null || die "pvesm nicht gefunden."
command -v pvesh >/dev/null || die "pvesh nicht gefunden."

# VMID
if [ "$VMID" = "auto" ]; then
  VMID="$(pvesh get /cluster/nextid)"
  log "Auto-VMID: $VMID"
fi
if qm status "$VMID" >/dev/null 2>&1; then die "VMID $VMID existiert bereits."; fi

# Bridge
if [ "$BRIDGE" = "auto" ]; then
  if ip link show vmbr0 >/dev/null 2>&1; then BRIDGE="vmbr0";
  else BRIDGE="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^vmbr[0-9]+' | head -n1)";
  fi
  [ -n "${BRIDGE:-}" ] || die "Keine vmbr gefunden. Bitte --bridge angeben."
  log "Auto-Bridge: $BRIDGE"
fi

# Storage mit Content-Filter + meistem Platz
pick_storage() {
  local content="$1"
  pvesm status --content "$content" 2>/dev/null \
    | awk 'NR>1 && $2!="0" {print $1, $6}' | sort -k2 -n | tail -n1 | awk '{print $1}'
}
if [ "$IMG_STORAGE" = "auto" ]; then
  IMG_STORAGE="$(pick_storage images || true)"
  [ -n "${IMG_STORAGE:-}" ] || die "Kein Storage mit Content 'images' gefunden."
  log "Auto-Image-Storage: $IMG_STORAGE"
fi
if [ "$ISO_STORAGE" = "auto" ]; then
  ISO_STORAGE="$(pick_storage iso || true)"
  [ -n "${ISO_STORAGE:-}" ] || die "Kein Storage mit Content 'iso' gefunden."
  log "Auto-ISO-Storage: $ISO_STORAGE"
fi

ISO_DIR="$(pvesm path "$ISO_STORAGE:iso/dummy" 2>/dev/null | xargs dirname 2>/dev/null || true)"
if [ -z "${ISO_DIR:-}" ] || [ ! -d "$ISO_DIR" ]; then
  # Fallback Standardpfad
  ISO_DIR="/var/lib/vz/template/iso"
fi
mkdir -p "$ISO_DIR"

latest_iso_url() {
  local page iso
  page="$(curl -fsSL https://enterprise.proxmox.com/iso/ 2>/dev/null || true)"
  iso="$(echo "$page" | grep -oE 'proxmox-backup-server_[0-9]+\.[0-9-]+1\.iso' | sort -V | tail -n1)"
  [ -n "${iso:-}" ] || return 1
  echo "https://enterprise.proxmox.com/iso/$iso"
}

ISO_FILE=""
if [ "$ISO_URL" = "auto" ]; then
  # vorhandene ISO wiederverwenden?
  ISO_FILE="$(ls -1 "$ISO_DIR"/proxmox-backup-server_*.iso 2>/dev/null | sort -V | tail -n1 || true)"
  if [ -n "${ISO_FILE:-}" ]; then
    log "Vorhandene ISO: $ISO_FILE"
  else
    ISO_URL="$(latest_iso_url)" || die "Konnte neueste ISO-URL nicht ermitteln. Bitte --iso-url angeben."
    log "Neueste ISO-URL: $ISO_URL"
  fi
fi
if [ -z "${ISO_FILE:-}" ]; then
  [ "$ISO_URL" != "auto" ] || die "Keine ISO-URL."
  ISO_FILE="$ISO_DIR/$(basename "$ISO_URL")"
  if [ ! -f "$ISO_FILE" ]; then
    log "Lade ISO herunter (kann dauern): $ISO_URL"
    if [ "$DRY_RUN" -eq 1 ]; then echo "+ curl -fSL -o $ISO_FILE $ISO_URL";
    else curl -fSL -o "$ISO_FILE" "$ISO_URL"; fi
  else
    log "ISO bereits vorhanden: $ISO_FILE"
  fi
fi
ISO_VOL="$ISO_STORAGE:iso/$(basename "$ISO_FILE")"

log "Erstelle VM $VMID ($VM_NAME): $CORES Cores, ${MEMORY}MB RAM, OS $OS_DISK_SIZE auf $IMG_STORAGE"
run "qm create $VMID --name $VM_NAME --cores $CORES --memory $MEMORY --cpu $CPU_TYPE --machine q35 --bios ovmf --ostype l26 --scsihw virtio-scsi-pci --net0 virtio,bridge=$BRIDGE --efidisk0 $IMG_STORAGE:1,efitype=4m,pre-enrolled-keys=1"
run "qm set $VMID --scsi0 $IMG_STORAGE:$OS_DISK_SIZE,iothread=1,discard=on,ssd=1"
if [ "$DATA_DISK_SIZE" != "0" ] && [ "$DATA_DISK_SIZE" != "0G" ]; then
  DATA_DISK_SIZE="$(norm_g "$DATA_DISK_SIZE")"
  log "Extra Datastore-Disk: $DATA_DISK_SIZE"
  run "qm set $VMID --scsi1 $IMG_STORAGE:$DATA_DISK_SIZE,iothread=1,discard=on,ssd=1"
fi
run "qm set $VMID --ide2 $ISO_VOL,media=cdrom --boot order=scsi0\\;ide2 --serial0 socket --vga serial0"

ANSWER_ISO=""
if [ "$MODE" = "unattended" ]; then
  log "Unattended-Modus: erzeuge answer.toml"
  command -v genisoimage >/dev/null || command -v xorriso >/dev/null || log "WARN: weder genisoimage noch xorriso gefunden - Answer-ISO wird evtl. nicht gebaut."
  ROOTPW="${PBS_ROOT_PASSWORD:-}"
  [ -n "${ROOTPW:-}" ] || { log "HINWEIS: PBS_ROOT_PASSWORD nicht gesetzt - nutze Default 'pbs-auto-123'. Bitte nach Install aendern!"; ROOTPW="pbs-auto-123"; }
  ANS_DIR="$(mktemp -d)"
  cat > "$ANS_DIR/answer.toml" <<EOF2
[global]
keyboard = "de"
country = "de"
fqdn = "${VM_NAME}.local"
mailto = "root@localhost"
timezone = "Europe/Berlin"
root-password = "$ROOTPW"

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk-list = ["vda"]
EOF2
  ANSWER_ISO="$ISO_DIR/pbs-answer-$VMID.iso"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "+ genisoimage Answer-ISO -> $ANSWER_ISO"
  else
    if command -v genisoimage >/dev/null; then
      genisoimage -o "$ANSWER_ISO" -V "PBSANSWER" -J -r "$ANS_DIR" >/dev/null
    elif command -v xorriso >/dev/null; then
      xorriso -as mkisofs -o "$ANSWER_ISO" -V "PBSANSWER" -J -r "$ANS_DIR" >/dev/null
    else
      log "WARN: kein ISO-Tool - unattended ohne Answer-ISO, falle auf manuell zurueck."
      MODE="manual"
    fi
  fi
  rm -rf "$ANS_DIR"
  if [ "$MODE" = "unattended" ]; then
    run "qm set $VMID --ide3 $ISO_STORAGE:iso/$(basename "$ANSWER_ISO"),media=cdrom"
    log "Answer-ISO eingebunden. PBS-Auto-Installer startet ab PBS 3.1 automatisch."
  fi
fi

log "Fertig. VM $VMID angelegt."
if [ "$MODE" = "manual" ]; then
  cat <<EOF
Naechste Schritte (manueller Installer):
  1) qm start $VMID
  2) Konsole oeffnen: qm terminal $VMID  (oder GUI -> Konsole)
  3) PBS installieren (Zielplatte: 32G OS-Disk), danach ISO auswerfen:
       qm set $VMID --delete ide2
  4) Datastore anlegen (falls extra Disk): GUI -> PBS -> Datastore, z.B. /mnt/datastore
Einzeiler fuer spaeter:
  qm start $VMID && qm terminal $VMID
EOF
else
  cat <<EOF
Unattended angelegt. Start mit:
  qm start $VMID
Danach Web-UI: https://<dhcp-ip>:8007 (User root)
Root-Passwort: aus Env PBS_ROOT_PASSWORD oder Default (bitte sofort aendern).
Nach Installation ISO auswerfen:
  qm set $VMID --delete ide2; qm set $VMID --delete ide3
EOF
fi
