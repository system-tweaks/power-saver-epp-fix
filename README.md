# power-saver-epp-fix

<p align="center">
  <img src="assets/power-saver-epp-fix.png" alt="Power Saver EPP Fix project artwork" width="900">
</p>

> Hinweis / Note: Das Bild ist Projekt-Artwork. Die aktuelle Implementierung
> richtet sich an Linux/systemd mit `power-profiles-daemon` und Intel EPP.

## Deutsch

`power-saver-epp-fix` ist ein kleiner systemd-Override für Linux-Systeme mit
`power-profiles-daemon` und Intel `intel_pstate`/HWP. Er behält das GNOME-Profil
`power-saver` bei, setzt die CPU-EPP-Vorgabe aber abhängig von der Stromquelle:
am Akku immer auf `power`, am Netz standardmäßig auf `balance_power` (beim
Setup auf `power` umstellbar, siehe Installation).

Optional kann zusätzlich ein `platform_profile`-Guard installiert werden. Dieser
entkoppelt `power-profiles-daemon` vom ACPI-`platform_profile`-Treiber und hält
das Hardware-Profil passend zum manuell gewählten GNOME-Profil. Manuelle
Profilwechsel bleiben normal möglich; automatische Rückwechsel durch
`platform_profile`-Drift werden verhindert.

Das hilft auf Systemen, bei denen der Energiesparmodus zwar den Lüfter ruhig
hält, aber Maus, UI, Browser oder Audio wegen zu träger CPU-Reaktion ruckeln.

### Was wird geändert?

GNOME wählt nur das Power-Profil:

```text
power-saver / balanced / performance
```

Die konkrete CPU- und Plattform-Policy kommt von `power-profiles-daemon`. Auf
manchen Intel-Systemen bedeutet `power-saver`:

```text
platform_profile = low-power
CPU EPP          = power
```

Ohne Guard lässt dieses Projekt `platform_profile=low-power` unverändert und
setzt vor allem:

```text
power-saver am Akku: CPU EPP = power
power-saver am Netz: CPU EPP = balance_power (Standard, per --epp-ac wählbar)
balanced am Akku:    CPU EPP = balance_power
balanced am Netz:    CPU EPP = balance_performance
performance:         CPU EPP = performance
```

Mit Guard wird zusätzlich `platform_profile` aus dem manuell gewählten Profil
abgeleitet:

```text
power-saver  -> platform_profile = low-power
balanced     -> platform_profile = balanced
performance  -> platform_profile = performance
```

Der Guard setzt kein festes Wunschprofil. Wenn du manuell `balanced` wählst,
bleibt `balanced` gültig. Wenn du manuell `power-saver` wählst, bleibt
`power-saver` gültig.

### Kompatibilität

Gedacht für:

- Linux mit systemd
- `power-profiles-daemon`
- Intel `intel_pstate`/HWP
- CPUs mit `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference`
- Systeme, die den EPP-Wert `power` anbieten (`balance_power` zusätzlich,
  falls am Netz gewünscht)
- Optional für den Guard: `/sys/firmware/acpi/platform_profile`

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

Mit Schutz gegen automatische `platform_profile`-Rückwechsel:

```bash
sudo ./install.sh --platform-profile-guard
```

Der Installer fragt standardmäßig interaktiv (Ja ist vorausgewählt), ob im
Profil `power-saver` am Netz `balance_power` statt `power` gelten soll. Am
Akku bleibt es immer bei `power`. Für nicht-interaktive Installationen kann
die Netz-EPP über eine Option vorgegeben werden:

```bash
sudo ./install.sh --epp-ac=balance_power --non-interactive
```

Die Auswahl landet in `/etc/power-saver-epp-fix/epp.conf` und wird von
`ppd-epp-override` bei jedem Lauf eingelesen.

Installiert werden:

```text
/usr/local/sbin/ppd-epp-override
/etc/systemd/system/ppd-epp-override.service
/etc/systemd/system/ppd-epp-override.path
/etc/udev/rules.d/99-ppd-epp-override.rules
/etc/power-saver-epp-fix/epp.conf
```

Zusätzlich im Guard-Modus:

```text
/etc/systemd/system/ppd-epp-override.timer
/etc/systemd/system/power-profiles-daemon.service.d/10-platform-profile-guard.conf
```

Die Path-Unit überwacht sowohl Zustandsänderungen von `power-profiles-daemon`
als auch `platform_profile`-Drift. Der Timer ist ein Fallback für
Firmware-Änderungen, die kein nutzbares Datei-Änderungsereignis auslösen.

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

Im Profil `power-saver` sollte danach je nach Stromquelle erscheinen
(sofern beim Setup keine abweichende Netz-EPP gewählt wurde):

```text
Akku: 8 power
Netz: 8 balance_power
```

Die Zahl kann je nach CPU-Kern-/Thread-Anzahl abweichen.

Im Guard-Modus sollte zusätzlich gelten:

```text
power-saver  -> platform_profile = low-power
balanced     -> platform_profile = balanced
performance  -> platform_profile = performance
```

### Deinstallation

```bash
sudo ./uninstall.sh
```

### Was dieses Projekt nicht ist

- kein GNOME-Patch
- kein Fork von `power-profiles-daemon`
- kein globaler Performance-Modus
- kein Profil-Pin, der manuelle Wechsel blockiert

## English

`power-saver-epp-fix` is a small systemd override for Linux systems using
`power-profiles-daemon` with Intel `intel_pstate`/HWP. It keeps the GNOME
`power-saver` profile active, but automatically sets the CPU EPP hint based on
the current power source: always `power` on battery, and by default
`balance_power` on AC (switchable to `power` during setup, see Installation).

It can optionally install a `platform_profile` guard. The guard disconnects
`power-profiles-daemon` from the ACPI `platform_profile` driver and lets this
tool keep the hardware platform profile aligned with the manually selected
GNOME power profile. Manual profile switching still works; automatic switches
caused by `platform_profile` drift are prevented.

This helps on systems where power saver keeps the fan quiet, but makes the
mouse, UI, browser, or audio feel sluggish because CPU wake-up behavior is too
conservative.

### What changes?

GNOME only selects the high-level power profile:

```text
power-saver / balanced / performance
```

The concrete CPU and platform policy is applied by `power-profiles-daemon`. On
some Intel systems, `power-saver` means:

```text
platform_profile = low-power
CPU EPP          = power
```

Without the guard, this project leaves `platform_profile=low-power` untouched
and mainly applies:

```text
power-saver on battery: CPU EPP = power
power-saver on AC:      CPU EPP = balance_power (default, choose via --epp-ac)
balanced on battery:    CPU EPP = balance_power
balanced on AC:         CPU EPP = balance_performance
performance:            CPU EPP = performance
```

With the guard enabled, `platform_profile` is derived from the manually selected
profile:

```text
power-saver  -> platform_profile = low-power
balanced     -> platform_profile = balanced
performance  -> platform_profile = performance
```

The guard does not pin one desired profile. If you manually select `balanced`,
`balanced` remains valid. If you manually select `power-saver`, `power-saver`
remains valid.

### Compatibility

Intended for:

- Linux with systemd
- `power-profiles-daemon`
- Intel `intel_pstate`/HWP
- CPUs exposing `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference`
- systems advertising the EPP value `power` (`balance_power` too, if wanted
  on AC)
- Optional for the guard: `/sys/firmware/acpi/platform_profile`

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

With protection against automatic `platform_profile` switches:

```bash
sudo ./install.sh --platform-profile-guard
```

By default the installer interactively asks (Yes is preselected) whether the
`power-saver` profile should use `balance_power` instead of `power` on AC.
On battery it always stays `power`. For non-interactive installs the AC EPP
can be provided via a flag instead:

```bash
sudo ./install.sh --epp-ac=balance_power --non-interactive
```

The choice is stored in `/etc/power-saver-epp-fix/epp.conf` and read by
`ppd-epp-override` on every run.

Installed files:

```text
/usr/local/sbin/ppd-epp-override
/etc/systemd/system/ppd-epp-override.service
/etc/systemd/system/ppd-epp-override.path
/etc/udev/rules.d/99-ppd-epp-override.rules
/etc/power-saver-epp-fix/epp.conf
```

Additional files in guard mode:

```text
/etc/systemd/system/ppd-epp-override.timer
/etc/systemd/system/power-profiles-daemon.service.d/10-platform-profile-guard.conf
```

The path unit watches both `power-profiles-daemon` state changes and
`platform_profile` drift. The timer is a fallback for firmware changes that do
not emit a usable file-change event.

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

In the `power-saver` profile, the result should depend on the current power
source (unless a different AC EPP was chosen during setup):

```text
Battery: 8 power
AC:      8 balance_power
```

The number can differ depending on CPU core/thread count.

In guard mode, the platform profile should also match:

```text
power-saver  -> platform_profile = low-power
balanced     -> platform_profile = balanced
performance  -> platform_profile = performance
```

### Uninstall

```bash
sudo ./uninstall.sh
```

### Non-goals

- no GNOME patch
- no `power-profiles-daemon` fork
- no global performance mode
- no profile pin that blocks manual switching
