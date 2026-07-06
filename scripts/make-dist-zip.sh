#!/bin/bash
# make-dist-zip.sh — assemble a portable Windows ZIP of mudlark.
#
# Produces a self-contained ZIP that runs without MSYS2 installed.
# Layout inside the ZIP:
#
#   mudlark-<version>/
#     mudlark.exe               — main binary
#     mudlark.cmd               — launcher (sets MUDLARK_HOME, then runs exe)
#     README-PORTABLE.txt       — quick-start instructions
#     share/
#       mudlark/lisp/init.lisp
#       mudlark/lisp/contrib/*.lisp
#       emacs/site-lisp/tintin-mode.el
#     *.dll                     — all runtime DLL dependencies
#
# Usage (invoked from the top-level Makefile):
#   make dist-portable
#
# Or directly:
#   scripts/make-dist-zip.sh [BUILD_DIR] [OUTPUT_DIR]
#
# BUILD_DIR defaults to "build", OUTPUT_DIR defaults to ".".
# The resulting file is mudlark-<version>-windows-x86_64.zip.

set -eu

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$SRC_DIR/build}"
OUTPUT_DIR="${2:-$SRC_DIR}"

# Get version from the same script configure uses
VERSION="$("$SRC_DIR/build-aux/git-version.sh" "$SRC_DIR" 2>/dev/null || echo "0.0.0-unknown")"

# --- Binary ----------------------------------------------------------------
REAL_EXE="$BUILD_DIR/src/mudlark.exe"
if [ -f "$BUILD_DIR/src/.libs/mudlark.exe" ]; then
	REAL_EXE="$BUILD_DIR/src/.libs/mudlark.exe"
fi

# Detect target architecture from the built binary
ARCH=$(file "$REAL_EXE" 2>/dev/null | grep -oq 'ARM64\|aarch64' && echo "aarch64" || echo "x86_64")
PKG_NAME="mudlark-${VERSION}-windows-${ARCH}"
STAGE_DIR="$OUTPUT_DIR/$PKG_NAME"
ZIP_FILE="$OUTPUT_DIR/${PKG_NAME}.zip"

echo "==> Packaging mudlark $VERSION"

# Fresh staging directory
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/share/mudlark/lisp/contrib" \
	"$STAGE_DIR/share/emacs/site-lisp"

echo "==> Copying mudlark.exe (from $REAL_EXE)"
cp "$REAL_EXE" "$STAGE_DIR/mudlark.exe"

# --- Data files ------------------------------------------------------------
echo "==> Copying data files (lisp scripts, emacs)"
cp "$SRC_DIR/lisp/init.lisp" \
	"$STAGE_DIR/share/mudlark/lisp/init.lisp"
for f in "$SRC_DIR"/lisp/contrib/*.lisp; do
	cp "$f" "$STAGE_DIR/share/mudlark/lisp/contrib/"
done

# Emacs integration
if [ -f "$SRC_DIR/emacs/tintin-mode.el" ]; then
	cp "$SRC_DIR/emacs/tintin-mode.el" \
		"$STAGE_DIR/share/emacs/site-lisp/tintin-mode.el"
fi

# --- Runtime DLLs ----------------------------------------------------------
echo "==> Bundling runtime DLLs"
# Recursively resolve DLL dependencies via ldd, filtering out Windows system
# DLLs (those live in System32 and are always present on the user's machine).
SYSTEM_DLLS='ADVAPI32|KERNEL32|msvcrt|USER32|GDI32|SHELL32|ole32|OLE32|COMDLG32|SHLWAPI|WS2_32|WINSPOOL|VERSION|WINMM|IMM32|powrprof|PSAPI|DNSAPI|IPHLPAPI|WINHTTP|Secur32|SSPICLI|BCRYPT|NCRYPT|NTDLL|RPCRT4|SETUPAPI|CFGMG32|DEVOBJ|dwmapi|dwrite|D3D|DXGI|windows.storage|processthreadsapi|kernelbase|ucrtbase|msvcp|api-ms-win|win32u|combase|SHCORE|clbcat|propsys|MMDevApi|USERENV|AUTHZ|cryptbase|wldap32|wkscli|netutils|SAMLIB|secur32|SensApi|dpapi|apphelp|sechost|gdi32full|OLEAUT32|USP10|cfgmgr32|schannel|msvcp_win|gpapi|devobj|xtajit'

QUEUE="$(mktemp)"
SEEN="$(mktemp)"
echo "$REAL_EXE" >"$QUEUE"

while [ -s "$QUEUE" ]; do
	current="$(head -1 "$QUEUE")"
	tail -n +2 "$QUEUE" >"$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"

	[ -z "$current" ] && continue
	[ ! -f "$current" ] && continue

	echo "  ldd: $(basename "$current")"
	LDD_OUT="$(timeout 10 ldd "$current" 2>&1)"
	LDD_RC=$?
	if [ "$LDD_RC" -ne 0 ]; then
		echo "  WARNING: ldd timed out or failed (rc=$LDD_RC) on: $current"
		continue
	fi
	for dll in $(echo "$LDD_OUT" |
		grep -i '\.dll' | awk '{print $3}'); do
		[ -z "$dll" ] && continue
		[ ! -f "$dll" ] && continue
		base="$(basename "$dll")"
		if echo "$base" | grep -iqE "^($SYSTEM_DLLS)"; then
			continue
		fi
		if grep -qxF "$base" "$SEEN" 2>/dev/null; then
			continue
		fi
		echo "$base" >>"$SEEN"
		cp "$dll" "$STAGE_DIR/"
		echo "  bundled: $base"
		echo "$dll" >>"$QUEUE"
	done
done

rm -f "$QUEUE" "$SEEN"

# --- Launcher script -------------------------------------------------------
echo "==> Writing launcher script"
cat >"$STAGE_DIR/mudlark.cmd" <<'LAUNCHER'
@echo off
:: mudlark.cmd — launcher for portable mudlark
:: Sets MUDLARK_HOME so the Lisp loader finds share/mudlark/lisp,
:: then starts mudlark.exe. All paths are relative to this script.
setlocal
set "HERE=%~dp0"
set "MUDLARK_HOME=%HERE%share\mudlark"
for %%I in ("%HERE%mudlark.exe") do set "MUDLARK_EXE=%%~fI"
"%MUDLARK_EXE%" %*
endlocal
LAUNCHER

# --- README ----------------------------------------------------------------
echo "==> Writing README-PORTABLE.txt"
cat >"$STAGE_DIR/README-PORTABLE.txt" <<'README'
Mudlark (Portable)
==================

This is a self-contained build of mudlark — no MSYS2 installation required.

Quick start:
  1. Extract the ZIP anywhere.
  2. Double-click mudlark.cmd (or mudlark.exe directly).

mudlark.cmd sets up MUDLARK_HOME so the embedded Lisp scripting layer
finds its files (init.lisp, TinTin++ modules). If you run mudlark.exe
directly from the extracted folder, it will still find them via the
executable's own directory detection.

To create a Start Menu shortcut:
  Right-click mudlark.cmd > Create shortcut
  Move the shortcut to: %AppData%\Microsoft\Windows\Start Menu\Programs\

To uninstall:
  Delete the folder. mudlark stores no data outside its own directory.
README

# --- Create ZIP ------------------------------------------------------------
echo "==> Creating ZIP: $(basename "$ZIP_FILE")"
rm -f "$ZIP_FILE"
ZIPPED=0
if command -v zip >/dev/null 2>&1; then
	(cd "$OUTPUT_DIR" && zip -r -9 "$ZIP_FILE" "$PKG_NAME" >/dev/null) && ZIPPED=1
fi
if [ "$ZIPPED" -ne 1 ] && command -v 7z >/dev/null 2>&1; then
	win_zip="$(cygpath -w "$ZIP_FILE" 2>/dev/null || echo "$ZIP_FILE")"
	win_pkg="$(cygpath -w "$PKG_NAME" 2>/dev/null || echo "$PKG_NAME")"
	(cd "$OUTPUT_DIR" && 7z a -tzip -mx=9 "$win_zip" "$win_pkg" >/dev/null) && ZIPPED=1
fi
if [ "$ZIPPED" -ne 1 ]; then
	# Fallback: PowerShell Compress-Archive (always available on Windows)
	win_stage="$(cygpath -w "$STAGE_DIR" 2>/dev/null || echo "$STAGE_DIR")"
	win_zip="$(cygpath -w "$ZIP_FILE" 2>/dev/null || echo "$ZIP_FILE")"
	powershell.exe -NoProfile -Command \
		"Compress-Archive -Path '$win_stage\\*' -DestinationPath '$win_zip' -Force" &&
		ZIPPED=1
fi
if [ "$ZIPPED" -ne 1 ]; then
	echo "ERROR: Cannot create ZIP (tried zip, 7z, PowerShell)" >&2
	echo " staged directory left at: $STAGE_DIR" >&2
	exit 1
fi

# Clean up staging dir
rm -rf "$STAGE_DIR"
echo "==> Done: $(basename "$ZIP_FILE")"
