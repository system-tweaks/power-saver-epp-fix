#!/bin/sh
set -eu

SUDO=

if [ "$(id -u)" -ne 0 ]; then
	if command -v sudo >/dev/null 2>&1; then
		SUDO=sudo
	else
		echo "This uninstaller must be run as root or with sudo available." >&2
		exit 1
	fi
fi

if command -v systemctl >/dev/null 2>&1; then
	for unit in ppd-epp-override.timer ppd-epp-override.path ppd-epp-override.service; do
		$SUDO systemctl disable --now "$unit" >/dev/null 2>&1 || true
	done
fi

$SUDO rm -f \
	/usr/local/sbin/ppd-epp-override \
	/etc/systemd/system/ppd-epp-override.service \
	/etc/systemd/system/ppd-epp-override.path \
	/etc/systemd/system/ppd-epp-override.timer \
	/etc/systemd/system/multi-user.target.wants/ppd-epp-override.service \
	/etc/systemd/system/multi-user.target.wants/ppd-epp-override.path \
	/etc/systemd/system/timers.target.wants/ppd-epp-override.timer \
	/etc/systemd/system/power-profiles-daemon.service.d/10-platform-profile-guard.conf \
	/etc/udev/rules.d/99-ppd-epp-override.rules \
	/etc/power-saver-epp-fix/epp.conf

$SUDO rmdir /etc/power-saver-epp-fix 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
	$SUDO systemctl daemon-reload
	# A failed restart here would leave power-profiles-daemon running with a
	# stale merged config (e.g. a removed platform_profile-guard drop-in that
	# never actually took effect) until something else restarts it later, so
	# surface the failure instead of swallowing it silently.
	if ! $SUDO systemctl restart power-profiles-daemon.service; then
		echo "Warning: failed to restart power-profiles-daemon.service; run 'sudo systemctl restart power-profiles-daemon.service' manually." >&2
	fi
fi
if command -v udevadm >/dev/null 2>&1; then
	$SUDO udevadm control --reload-rules
fi

echo "Removed power-saver EPP override."
