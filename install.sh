#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUDO=

if [ "$(id -u)" -ne 0 ]; then
	if command -v sudo >/dev/null 2>&1; then
		SUDO=sudo
	else
		echo "This installer must be run as root or with sudo available." >&2
		exit 1
	fi
fi

require_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1" >&2
		exit 1
	fi
}

require_command install
require_command systemctl
require_command powerprofilesctl

if [ ! -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
	echo "No CPU cpufreq sysfs interface found. Nothing was installed." >&2
	exit 1
fi

if [ ! -r /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
	echo "CPU EPP sysfs interface not found. This tool is intended for systems exposing energy_performance_preference." >&2
	exit 1
fi

if ! grep -qw balance_power /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null &&
	! grep -qw balance_power /sys/devices/system/cpu/cpu0/cpufreq/available_energy_performance_preferences 2>/dev/null; then
	echo "CPU EPP value 'balance_power' is not advertised by this system. Nothing was installed." >&2
	exit 1
fi

$SUDO install -D -m 0755 "$SCRIPT_DIR/src/ppd-epp-override" /usr/local/sbin/ppd-epp-override
$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.service" /etc/systemd/system/ppd-epp-override.service
$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.path" /etc/systemd/system/ppd-epp-override.path

$SUDO systemctl daemon-reload
$SUDO systemctl enable --now ppd-epp-override.service ppd-epp-override.path

echo "Installed power-saver EPP override."
echo
printf "profile="
powerprofilesctl get 2>/dev/null || true
printf "platform_profile="
cat /sys/firmware/acpi/platform_profile 2>/dev/null || true
printf "epp: "
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/energy_performance_preference; do
	[ -r "$f" ] && cat "$f"
done | sort | uniq -c
