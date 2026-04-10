#!/bin/bash

FLATPAK="/usr/bin/flatpak.real"

error() {
	echo "E: $@" >&2
	exit 1
}

# Detect if script is called by completion function
if [[ "$COMP_LINE" != "" || "$1" == "complete" ]]; then
	exec "$FLATPAK" "$@"
fi

# Get triplet
case "$(dpkg --print-architecture)" in
	"amd64")
		TRIPLET="x86_64-linux-gnu"
		;;
	"i386")
		TRIPLET="i386-linux-gnu"
		;;
	"arm64")
		TRIPLET="aarch64-linux-gnu"
		;;
	"armhf")
		TRIPLET="arm-linux-gnueabihf"
		;;
	*)
		error "Unable to obtain triplet"
		;;
esac

EXTRA_FLAGS=()
[ -e /run/user/${UID}/wayland-0 ] && \
	EXTRA_FLAGS+=("--filesystem=/run/user/${UID}/wayland-0:ro")
[ -e /run/dbus/system_bus_socket ] && \
	EXTRA_FLAGS+=("--filesystem=/run/dbus/system_bus_socket:ro")

# Get libdir
if [ $(getconf LONG_BIT) == 32 ]; then
	LIBDIR="lib"
else
	LIBDIR="lib64"
fi

[ -z "${HYBRIS_LD_LIBRARY_PATH}" ] && \
	HYBRIS_LD_LIBRARY_PATH="/system/${LIBDIR}:/vendor/${LIBDIR}:/odm/${LIBDIR}"

if [[ "$@" =~ 'run ' ]]; then
	# Flatpak should be ran, ensure we attach our own arguments

	args=("$@")

	# Find the app ID: first non-flag argument after "run"
	app_id=""
	seen_run=0
	for a in "${args[@]}"; do
		if [[ $seen_run -eq 0 ]]; then
			[[ "$a" == "run" ]] && seen_run=1
			continue
		fi
		[[ "$a" == -* ]] && continue
		app_id="$a"
		break
	done

	if [[ -n "$app_id" ]]; then
		sdk=$("$FLATPAK" info "$app_id" 2>/dev/null | awk -F': *' '/^Sdk:/ {print $2}')
		if [[ "$sdk" != org.kde.Sdk/*/6.* ]]; then
		    echo "Warning: App $app_id is not using a KDE SDK 6 runtime, GL drivers may not work properly"
			export FLATPAK_GL_DRIVERS="hybris"
		fi
	fi

	exec ${FLATPAK} \
		--filesystem=/system:ro \
		--filesystem=/vendor:ro \
		--filesystem=/odm:ro \
		--filesystem=/apex:ro \
		--filesystem=/android:ro \
		--filesystem=/mnt:ro \
		--filesystem=/data:ro \
		--device=all \
		--env=LD_PRELOAD=libtls-padding.so:libglesshadercache.so \
		--env=HYBRIS_EGLPLATFORM_DIR=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris \
		--env=HYBRIS_LINKER_DIR=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris/linker \
		--env=HYBRIS_LD_LIBRARY_PATH=${HYBRIS_LD_LIBRARY_PATH} \
		--env=LD_LIBRARY_PATH=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris-egl:/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR} \
		"${EXTRA_FLAGS[@]}" \
		"${args[@]}"
else
	# Pass-through to the real executable
	exec "${FLATPAK}" "$@"
fi
