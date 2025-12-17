#!/bin/bash

# Only support x86_64 Debian-based and RHEL-based systems (for now...)
if [[ "$(arch)" != "x86_64" ]]; then
  echo "ERROR: This bootstrap script only supports x86_64 architecture."
  exit 1
fi

# If core utils isn't installed, then you have bigger problems because the package manager is also likely missing...
if ! command -v readlink >/dev/null 2>&1; then
  echo "ERROR: readlink is missing. Is coreutils installed?"
  exit 1
fi

# Parse argument
if [[ "$1" == "no-download" ]]; then
  rundownload="no"
else
  rundownload="yes"
fi

set -eu
declare -A LINKS

# Detect package manager and set download links
if command -v apt >/dev/null 2>&1; then
    PM=apt
    deburl=http://ftp.de.debian.org/debian/pool/main
    LINKS['util-linux']="$deburl/u/util-linux/util-linux_2.36.1-8+deb11u2_amd64.deb"
    LINKS['libfakeroot']="$deburl/f/fakeroot/libfakeroot_1.25.3-1.1_amd64.deb"
    LINKS['fakeroot']="$deburl/f/fakeroot/fakeroot_1.25.3-1.1_amd64.deb"
    if ! command -v dpkg >/dev/null 2>&1; then
      echo "ERROR: dpkg is required for Debian-based systems."
      exit 1
    fi
    BOOTSTRAP_OS="Debian 11"
elif command -v dnf >/dev/null 2>&1; then
    PM=dnf
    fedurl=https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages
    rhelurl=https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi8/8/x86_64/baseos/os/Packages
    LINKS['util-linux']="$rhelurl/u/util-linux-2.32.1-46.el8.x86_64.rpm"
    LINKS['libfakeroot']="$fedurl/f/fakeroot-libs-1.33-1.el8.x86_64.rpm"
    LINKS['fakeroot']="$fedurl/f/fakeroot-1.33-1.el8.x86_64.rpm"
    if ! command -v rpm2cpio >/dev/null 2>&1; then
      echo "ERROR: rpm2cpio is required for RHEL-based systems."
      exit 1
    fi
    BOOTSTRAP_OS="EPEL 8"
else
    echo "ERROR: apt or dnf package manager is required."
    exit 1
fi

echo "---- Boostrap install Fakeroot from $BOOTSTRAP_OS binaries (GLIBC 2.14) ----"
echo " Using package manager: $PM"
echo " System $(getconf GNU_LIBC_VERSION)"
echo ""

# Check for curl or wget, then download packages
if [[ $rundownload == "yes" ]]; then

  if command -v curl >/dev/null 2>&1; then
      download_cmd="curl -#O"

  elif command -v wget >/dev/null 2>&1; then
      download_cmd="wget"

  elif [[ $PM == "dnf" ]]; then
      # dnf can update repo list and install curl without fakeroot (in Apptainer build mode)
      dnf install -y curl
      download_cmd="curl -#O"

  else
      echo "ERROR: Required download utilities (curl or wget) are not available."
      echo ""
      echo "You can pre-download the necessary files on the Apptainer host system,"
      echo "then mount or copy them into the container and rerun this script using"
      echo "the 'no-download' option."
      echo ""
      echo "Download links:"
      for link in "${LINKS[@]}"; do
        echo "  $link"
      done
      echo ""
      exit 1
  fi

  function download() {
    local url="$1"
    echo "-> Downloading $url"
    if ! $download_cmd "$url"; then
      echo "ERROR: Failed to download $url"
      exit 1
    fi
  }

  # Download required packages
  if ! command -v getopt >/dev/null 2>&1; then
    download "${LINKS['util-linux']}"
  fi
  download "${LINKS['libfakeroot']}"
  download "${LINKS['fakeroot']}"

fi

INSTALL_DIR=/opt/fakeroot-bootstrap
mkdir -vp "$INSTALL_DIR"

# Note:
#  - If dnf is available, then rpm2cpio should also be available.
#  - If apt is available, then dpkg should also be available.

if [[ $PM == "dnf" ]]; then
  if ! command -v cpio >/dev/null 2>&1; then dnf install -y cpio; echo ""; fi
    echo "-> Extracting RPM packages"
    for item in *.rpm ; do
      (set -x; rpm2cpio "$item" | cpio -idv --no-preserve-owner -D "$INSTALL_DIR")
    done
  rm -v *.rpm
  lib64=lib64
else
  echo "-> Extracting DEB packages"
  for item in *.deb; do
    (set -x ; dpkg -x "$item" "$INSTALL_DIR")
  done
  rm -v *.deb
  lib64=lib/x86_64-linux-gnu
fi

echo "-> Patching fakeroot-sysv to use relative paths"
sed -i  -e 's,^FAKEROOT_PREFIX=/.*,FAKEROOT_BINDIR=${0%/*},' \
        -e 's,FAKEROOT_BINDIR=/.*,FAKEROOT_PREFIX=${FAKEROOT_BINDIR%/*},' \
        -e "s,^PATHS=/.*,PATHS=\${FAKEROOT_PREFIX}/${lib64}/libfakeroot," \
        $INSTALL_DIR/usr/bin/fakeroot-sysv

export PATH="$PATH:$INSTALL_DIR/usr/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$INSTALL_DIR/usr/$lib64"

echo "-> Finalizing fakeroot installation via package manager (update first)"
FAKEROOTDONTTRYCHOWN=1 fakeroot-sysv bash -c "
  $PM update -y
  # install EPEL for dnf-based systems, except Fedora
  if [[ \"$PM\" == 'dnf' ]] && ! grep -qi '^ID=.*fedora' /etc/os-release; then dnf install -y epel-release; fi
  $PM install -y fakeroot
"

# cleanup
(set -x && rm -rf "$INSTALL_DIR")
echo "removed directory '$INSTALL_DIR'"
