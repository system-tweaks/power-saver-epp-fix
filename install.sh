#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUDO=
platform_profile_guard=0

usage() {
	cat <<'EOF'
Usage: ./install.sh [--platform-profile-guard]

Options:
  --platform-profile-guard  Block power-profiles-daemon's platform_profile driver
                            and let this tool enforce platform_profile from the
                            manually selected power profile.
  -h, --help                Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--platform-profile-guard)
			platform_profile_guard=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
	shift
done

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

detect_power_source() {
	has_battery=0
	battery_discharging=0

	for supply in /sys/class/power_supply/*; do
		[ -d "$supply" ] || continue
		type="$(cat "$supply/type" 2>/dev/null || true)"
		online="$(cat "$supply/online" 2>/dev/null || true)"
		status="$(cat "$supply/status" 2>/dev/null || true)"

		if [ "$type" = "Battery" ]; then
			has_battery=1
			[ "$status" = "Discharging" ] && battery_discharging=1
			continue
		fi

		if [ "$online" = "1" ]; then
			printf '%s\n' ac
			return 0
		fi
	done

	if [ "$has_battery" -eq 1 ] && [ "$battery_discharging" -eq 1 ]; then
		printf '%s\n' battery
	else
		printf '%s\n' ac
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

if ! grep -qw power /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null &&
	! grep -qw power /sys/devices/system/cpu/cpu0/cpufreq/available_energy_performance_preferences 2>/dev/null; then
	echo "CPU EPP value 'power' is not advertised by this system. Nothing was installed." >&2
	exit 1
fi

if [ "$platform_profile_guard" -eq 1 ]; then
	if [ ! -r /sys/firmware/acpi/platform_profile ] || [ ! -r /sys/firmware/acpi/platform_profile_choices ]; then
		echo "ACPI platform_profile sysfs interface not found. Cannot install platform profile guard." >&2
		exit 1
	fi
	if [ ! -x /usr/libexec/power-profiles-daemon ]; then
		echo "Expected /usr/libexec/power-profiles-daemon was not found. Cannot install platform profile guard." >&2
		exit 1
	fi
fi

current_profile="$(powerprofilesctl get 2>/dev/null || true)"

$SUDO install -D -m 0755 "$SCRIPT_DIR/src/ppd-epp-override" /usr/local/sbin/ppd-epp-override
$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.service" /etc/systemd/system/ppd-epp-override.service
$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.path" /etc/systemd/system/ppd-epp-override.path
$SUDO install -D -m 0644 "$SCRIPT_DIR/udev/99-ppd-epp-override.rules" /etc/udev/rules.d/99-ppd-epp-override.rules

if [ "$platform_profile_guard" -eq 1 ]; then
	$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.timer" /etc/systemd/system/ppd-epp-override.timer
	$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/power-profiles-daemon-platform-guard.conf" \
		/etc/systemd/system/power-profiles-daemon.service.d/10-platform-profile-guard.conf
fi

$SUDO systemctl daemon-reload
if [ "$platform_profile_guard" -eq 1 ]; then
	$SUDO systemctl restart power-profiles-daemon.service
	if [ -n "$current_profile" ]; then
		powerprofilesctl set "$current_profile" 2>/dev/null || true
	fi
	$SUDO systemctl enable --now ppd-epp-override.service ppd-epp-override.path ppd-epp-override.timer
else
	$SUDO systemctl enable --now ppd-epp-override.service ppd-epp-override.path
fi
if command -v udevadm >/dev/null 2>&1; then
	$SUDO udevadm control --reload-rules
fi

echo "Installed power-saver EPP override."
if [ "$platform_profile_guard" -eq 1 ]; then
	echo "Installed platform_profile guard."
fi
echo
printf "profile="
powerprofilesctl get 2>/dev/null || true
printf "platform_profile="
cat /sys/firmware/acpi/platform_profile 2>/dev/null || true
printf "power_source="
detect_power_source
printf "epp: "
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/energy_performance_preference; do
	[ -r "$f" ] && cat "$f"
done | sort | uniq -c
