# power-saver-epp-fix

<p align="center">
  <img src="assets/power-saver-epp-fix.png" alt="Power Saver EPP Fix project artwork" width="900">
</p>

> Hinweis / Note: Das Bild ist Projekt-Artwork. Die aktuelle Implementierung
> richtet sich an Linux/systemd mit `power-profiles-daemon` und Intel EPP.

## Deutsch

`power-saver-epp-fix` ist ein kleiner systemd-Override für Linux-Systeme mit
`power-profiles-daemon` und Intel `intel_pstate`/HWP. Er behält das GNOME-Profil
`power-saver` bei, setzt die CPU-EPP-Vorgabe aber automatisch von `power` auf
`balance_power`.

Das hilft auf Systemen, bei denen der Energiesparmodus zwar den Lüfter ruhig
hält, aber Maus, UI, Browser oder Audio wegen zu träger CPU-Reaktion ruckeln.

### Was wird geändert?

GNOME wählt nur das Power-Profil:

```text
power-saver / balanced / performance
```

Die konkrete CPU-Policy kommt von `power-profiles-daemon`. Auf manchen Intel
Systemen bedeutet `power-saver`:

```text
platform_profile = low-power
CPU EPP          = power
```

Dieses Projekt lässt `platform_profile=low-power` unverändert und setzt nur:

```text
CPU EPP = balance_power
```

Der Override greift nur, wenn das aktive Profil `power-saver` ist.

### Kompatibilität

Gedacht für:

- Linux mit systemd
- `power-profiles-daemon`
- Intel `intel_pstate`/HWP
- CPUs mit `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference`
- Systeme, die den EPP-Wert `balance_power` anbieten

Getestet auf:

- Ubuntu 24.04.4 LTS
- GNOME Wayland
- Intel Core i7-8565U
- `power-profiles-daemon` 0.21

### Installation

```bash
git clone https://github.com/system-tweaks/power-saver-epp-fix.git
cd power-saver-epp-fix
sudo ./install.sh
```

Installiert werden:

```text
/usr/local/sbin/ppd-epp-override
/etc/systemd/system/ppd-epp-override.service
/etc/systemd/system/ppd-epp-override.path
```

### Verifikation

Aktives Profil:

```bash
powerprofilesctl get
```

Plattformprofil:

```bash
cat /sys/firmware/acpi/platform_profile
```

CPU-EPP:

```bash
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  cat "$f"
done | sort | uniq -c
```

Im GNOME-Profil `power-saver` sollte danach `balance_power` erscheinen:

```text
8 balance_power
```

### Deinstallation

```bash
sudo ./uninstall.sh
```

### Was dieses Projekt nicht ist

- kein GNOME-Patch
- kein Fork von `power-profiles-daemon`
- kein globaler Performance-Modus
- keine Änderung für `balanced` oder `performance`

## English

`power-saver-epp-fix` is a small systemd override for Linux systems using
`power-profiles-daemon` with Intel `intel_pstate`/HWP. It keeps the GNOME
`power-saver` profile active, but automatically changes the CPU EPP hint from
`power` to `balance_power`.

This helps on systems where power saver keeps the fan quiet, but makes the
mouse, UI, browser, or audio feel sluggish because CPU wake-up behavior is too
conservative.

### What changes?

GNOME only selects the high-level power profile:

```text
power-saver / balanced / performance
```

The concrete CPU policy is applied by `power-profiles-daemon`. On some Intel
systems, `power-saver` means:

```text
platform_profile = low-power
CPU EPP          = power
```

This project leaves `platform_profile=low-power` untouched and only applies:

```text
CPU EPP = balance_power
```

The override only runs when the active profile is `power-saver`.

### Compatibility

Intended for:

- Linux with systemd
- `power-profiles-daemon`
- Intel `intel_pstate`/HWP
- CPUs exposing `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference`
- systems advertising the EPP value `balance_power`

Tested on:

- Ubuntu 24.04.4 LTS
- GNOME Wayland
- Intel Core i7-8565U
- `power-profiles-daemon` 0.21

### Installation

```bash
git clone https://github.com/system-tweaks/power-saver-epp-fix.git
cd power-saver-epp-fix
sudo ./install.sh
```

Installed files:

```text
/usr/local/sbin/ppd-epp-override
/etc/systemd/system/ppd-epp-override.service
/etc/systemd/system/ppd-epp-override.path
```

### Verification

Active profile:

```bash
powerprofilesctl get
```

Platform profile:

```bash
cat /sys/firmware/acpi/platform_profile
```

CPU EPP:

```bash
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  cat "$f"
done | sort | uniq -c
```

In the GNOME `power-saver` profile, the result should include `balance_power`:

```text
8 balance_power
```

### Uninstall

```bash
sudo ./uninstall.sh
```

### Non-goals

- no GNOME patch
- no `power-profiles-daemon` fork
- no global performance mode
- no change for `balanced` or `performance`
