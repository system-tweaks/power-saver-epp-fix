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
	$SUDO systemctl disable --now ppd-epp-override.path ppd-epp-override.service >/dev/null 2>&1 || true
fi

$SUDO rm -f \
	/usr/local/sbin/ppd-epp-override \
	/etc/systemd/system/ppd-epp-override.service \
	/etc/systemd/system/ppd-epp-override.path

if command -v systemctl >/dev/null 2>&1; then
	$SUDO systemctl daemon-reload
fi

echo "Removed power-saver EPP override."
