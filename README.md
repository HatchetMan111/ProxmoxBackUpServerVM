# Proxmox Backup Server als VM (Einzeiler)

Installiert eine PBS-VM **als VM** (offiziell supportet) statt als LXC.
Das Script laeuft **auf dem PVE-Host als root**, erkennt VMID, Storage und Bridge automatisch und legt die VM mit offizieller PBS-ISO an.

## Einzeiler

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ProxmoxBackUpServerVM/main/pbs-vm-install.sh)"
```

### Danach: VM haendisch starten + Installer durchklicken

Der Einzeiler erstellt nur die VM fertig (Disks, Netz, ISO eingelegt) — **installiert wird haendisch**
im normalen visuellen PBS-Installer:

```bash
qm start <VMID>   # VMID steht in der Script-Ausgabe, z.B. qm start 104
```

Dann in der Proxmox-GUI auf die VM → **Konsole** und den Installer wie gewohnt durchgehen
(Sprache, Zeitzone, Root-Passwort, Zielplatte = OS-Disk, Netzwerk).
Zum Netzwerk: DHCP laeuft automatisch — falls dein Netz **kein DHCP** hat, im Installer
stattdessen statisch eintragen (z.B. `192.168.178.50/24`, Gateway `192.168.178.1`,
DNS `192.168.178.1`).

Nach erfolgreicher Installation Boot auf die Platte stellen und ISO auswerfen:

```bash
qm set <VMID> --boot 'order=scsi0' && qm set <VMID> --delete ide2 && qm start <VMID>
```

Danach ist PBS unter `https://<vm-ip>:8007` erreichbar. Tipp: Wer die IP schon vorher
festlegen will, gibt sie dem Script mit (`--ip-cidr ... --gateway ...`), dann steht sie
in der Abschluss-Anleitung.

## Beispiele

```bash
# nur zeigen, nichts erstellen
bash pbs-vm-install.sh --dry-run

# Standard (manueller Installer, 1x durchklicken)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/ProxmoxBackUpServerVM/main/pbs-vm-install.sh)"

# vollautomatisch per prepare-iso (PBS >= 3.2, DHCP)
sudo PBS_ROOT_PASSWORD='geheim' bash pbs-vm-install.sh --unattended

# vollautomatisch mit statischer IP (kein DHCP im Netz)
sudo PBS_ROOT_PASSWORD='geheim' bash pbs-vm-install.sh --unattended \
  --ip-cidr 192.168.178.50/24 --gateway 192.168.178.1

# manuell, aber mit statischer IP-Vorgabe (steht dann in der Anleitung)
bash pbs-vm-install.sh --ip-cidr 192.168.178.50/24 --gateway 192.168.178.1

# mit extra Datastore-Disk (100GB) + eigenem Namen
bash pbs-vm-install.sh --name pbs-main --data-disk 100 --cores 4 --memory 8192
```

## Warum VM statt LXC?

* Offiziell von Proxmox supportet (eigener Kernel, systemd, ZFS, Tape)
* Stabile Upgrades, HA/Live-Migration moeglich
* Community-Scripts nutzen LXC nur weil es leichter zu scripten und sparsamer ist, nicht weil es besser ist

## Hinweise

* Auf PVE 8/9 als `root` ausfuehren
* OS-Disk default 32GB (reine Zahl, LVM-Format), extra Datastore-Disk optional per `--data-disk`
* Bootreihenfolge waehrend Installation: ISO zuerst (`ide2;scsi0`), danach umstellen:
  `qm set <VMID> --boot 'order=scsi0' && qm set <VMID> --delete ide2`
* Manueller Modus nutzt Standard-VGA (Installer-TUI in noVNC bedienbar)
* Unattended nutzt den offiziellen Weg (`proxmox-auto-install-assistant prepare-iso`,
  wird bei Bedarf per apt nachinstalliert) mit `answer.toml` nach offizieller Doku
* Kein DHCP im Netz? `--ip-cidr` + `--gateway` mitgeben (DNS defaultet auf Gateway)
* Der hier im Chat gepostete Token wurde nicht ins Repo uebernommen. Neuen Token erstellen und per `git push` nutzen.
