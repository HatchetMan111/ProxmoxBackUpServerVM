# Proxmox Backup Server als VM (Einzeiler)

Installiert eine PBS-VM **als VM** (offiziell supportet) statt als LXC.
Das Script laeuft **auf dem PVE-Host als root**, erkennt VMID, Storage und Bridge automatisch und legt die VM mit offizieller PBS-ISO an.

## Einzeiler

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ProxmoxBackUpServerVM/main/pbs-vm-install.sh)"
```

## Beispiele

```bash
# nur zeigen, nichts erstellen
bash pbs-vm-install.sh --dry-run

# Standard (manueller Installer, 1x durchklicken)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ProxmoxBackUpServerVM/main/pbs-vm-install.sh)"

# vollautomatisch (PBS >= 3.1, DHCP)
sudo PBS_ROOT_PASSWORD='geheim' bash pbs-vm-install.sh --unattended

# mit extra Datastore-Disk (100G) + eigenem Namen
bash pbs-vm-install.sh --name pbs-main --data-disk 100 --cores 4 --memory 8192
```

## Warum VM statt LXC?

* Offiziell von Proxmox supportet (eigener Kernel, systemd, ZFS, Tape)
* Stabile Upgrades, HA/Live-Migration moeglich
* Community-Scripts nutzen LXC nur weil es leichter zu scripten und sparsamer ist, nicht weil es besser ist

## Hinweise

* Auf PVE 8/9 als `root` ausfuehren
* OS-Disk default 32G, extra Datastore-Disk optional per `--data-disk`
* Nach Installation ISO auswerfen: `qm set <VMID> --delete ide2`
* Der hier im Chat gepostete Token wurde nicht ins Repo uebernommen. Neuen Token erstellen und per `git push` nutzen.
