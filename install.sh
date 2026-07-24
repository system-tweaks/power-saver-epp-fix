#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUDO=
platform_profile_guard=0
epp_ac=
non_interactive=0
CONFIG_DIR=/etc/power-saver-epp-fix
CONFIG_FILE="$CONFIG_DIR/epp.conf"

usage() {
	cat <<'EOF'
Usage: ./install.sh [--platform-profile-guard] [--epp-ac=VALUE] [--non-interactive]

Options:
  --platform-profile-guard  Block power-profiles-daemon's platform_profile driver
                            and let this tool enforce platform_profile from the
                            manually selected power profile.
  --epp-ac=VALUE            CPU EPP preference to apply for the power-saver
                            profile while on AC power: "power" or
                            "balance_power". Skips the interactive prompt.
                            The battery EPP always stays "power".
  --non-interactive         Never prompt; fall back to "balance_power" (or
                            the value given via --epp-ac).
  -h, --help                Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--platform-profile-guard)
			platform_profile_guard=1
			;;
		--epp-ac=*)
			epp_ac="${1#--epp-ac=}"
			;;
		--non-interactive)
			non_interactive=1
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

get_available_epp() {
	for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/energy_performance_available_preferences \
		/sys/devices/system/cpu/cpu[0-9]*/cpufreq/available_energy_performance_preferences; do
		if [ -r "$f" ]; then
			cat "$f"
			return 0
		fi
	done
	return 1
}

# Same word-membership check as has_word() in src/ppd-epp-override; kept as a
# separate copy because the two scripts are deployed independently.
has_word() {
	case " $1 " in
		*" $2 "*) return 0 ;;
		*) return 1 ;;
	esac
}

epp_ac_is_valid() {
	case "$1" in
		power|balance_power) return 0 ;;
		*) return 1 ;;
	esac
}

# Ask whether the power-saver profile should use "balance_power" instead of
# "power" while on AC. Battery always stays "power". Prints the chosen value
# on stdout; the question itself goes to stderr.
prompt_epp_ac() {
	printf 'Soll fuer den Netzbetrieb das EPP-Profil von "power" auf "balance_power" angehoben werden? [J/n] ' >&2
	read -r answer || answer=
	case "$answer" in
		''|[JjYy]*)
			printf '%s\n' balance_power
			;;
		*)
			printf '%s\n' power
			;;
	esac
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

available_epp="$(get_available_epp)" || {
	echo "CPU EPP available-preferences sysfs file not found. This tool is intended for systems exposing energy_performance_available_preferences." >&2
	exit 1
}

if ! has_word "$available_epp" power; then
	echo "CPU EPP value 'power' is not advertised by this system: $available_epp. Nothing was installed." >&2
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

if [ "$non_interactive" -eq 0 ] && [ -t 0 ]; then
	[ -n "$epp_ac" ] || epp_ac="$(prompt_epp_ac)"
fi

epp_ac="${epp_ac:-balance_power}"
epp_battery=power

if ! epp_ac_is_valid "$epp_ac"; then
	echo "EPP value '$epp_ac' (--epp-ac) is not supported; use 'power' or 'balance_power'." >&2
	exit 1
fi
if ! has_word "$available_epp" "$epp_ac"; then
	echo "EPP value '$epp_ac' (--epp-ac) is not advertised by this system: $available_epp" >&2
	exit 1
fi

current_profile="$(powerprofilesctl get 2>/dev/null || true)"

tmp_conf="$(mktemp)"
trap 'rm -f "$tmp_conf"' EXIT
printf 'POWER_SAVER_EPP_AC=%s\n' "$epp_ac" > "$tmp_conf"
$SUDO install -D -m 0644 "$tmp_conf" "$CONFIG_FILE"

$SUDO install -D -m 0755 "$SCRIPT_DIR/src/ppd-epp-override" /usr/local/sbin/ppd-epp-override
$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.service" /etc/systemd/system/ppd-epp-override.service
$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.path" /etc/systemd/system/ppd-epp-override.path
$SUDO install -D -m 0644 "$SCRIPT_DIR/udev/99-ppd-epp-override.rules" /etc/udev/rules.d/99-ppd-epp-override.rules

guard_conf=/etc/systemd/system/power-profiles-daemon.service.d/10-platform-profile-guard.conf
guard_was_active=0
[ -e "$guard_conf" ] && guard_was_active=1

if [ "$platform_profile_guard" -eq 1 ]; then
	$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/ppd-epp-override.timer" /etc/systemd/system/ppd-epp-override.timer
	$SUDO install -D -m 0644 "$SCRIPT_DIR/systemd/power-profiles-daemon-platform-guard.conf" "$guard_conf"
else
	# Reconcile a previously installed guard: remove it rather than merely
	# skipping its install, otherwise a stale --block-driver=platform_profile
	# keeps running until some unrelated later restart picks up the change.
	$SUDO systemctl disable --now ppd-epp-override.timer >/dev/null 2>&1 || true
	$SUDO rm -f /etc/systemd/system/ppd-epp-override.timer \
		/etc/systemd/system/timers.target.wants/ppd-epp-override.timer \
		"$guard_conf"
fi

$SUDO systemctl daemon-reload

if [ "$platform_profile_guard" -ne "$guard_was_active" ]; then
	$SUDO systemctl restart power-profiles-daemon.service
	if [ -n "$current_profile" ]; then
		powerprofilesctl set "$current_profile" 2>/dev/null || true
	fi
fi

if [ "$platform_profile_guard" -eq 1 ]; then
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
echo "power-saver EPP: AC=$epp_ac battery=$epp_battery ($CONFIG_FILE)"
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
