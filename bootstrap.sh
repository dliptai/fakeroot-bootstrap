#!/bin/bash

if [[ "$1" == "no-download" ]]; then
  rundownload="no"
else
  rundownload="yes"
fi

set -eu

# Only works for Debian-based and RHEL-based systems (at least for now)
if command -v apt >/dev/null 2>&1; then
    PM="apt"
elif command -v dnf >/dev/null 2>&1; then
    PM="dnf"
else
    echo "ERROR: apt or dnf package manager is required."
    exit 1
fi

if [[ $rundownload == "yes" ]]; then
  # Check for curl or wget
  if command -v curl >/dev/null 2>&1; then
      download_cmd="curl -O"
  elif command -v wget >/dev/null 2>&1; then
      download_cmd="wget"
  elif [[ $PM == "dnf" ]]; then
      # dnf can run "dnf update" and install curl without fakeroot
      echo "-> Installing curl via package manager"
      $PM install -y curl
      download_cmd="curl -O"
  else
      echo "ERROR: Neither curl nor wget is installed. Cannot proceed."
      echo ""
      echo "You can try pre-downloading them on the apptainer host system,"
      echo "and then mounting/copying them into the container, and re-running"
      echo "this script with the argument 'no-download'"
      echo ""
      echo "Download links:"
      echo "  http://ftp.de.debian.org/debian/pool/main/u/util-linux/util-linux_2.36.1-8+deb11u2_amd64.deb"
      echo "  http://ftp.de.debian.org/debian/pool/main/f/fakeroot/libfakeroot_1.25.3-1.1_amd64.deb"
      echo "  http://ftp.de.debian.org/debian/pool/main/f/fakeroot/fakeroot_1.25.3-1.1_amd64.deb"
      exit 1
  fi
fi

# If core utils isn't installed, then you have bigger problems because the package manager is also likely missing...
if ! command -v readlink >/dev/null 2>&1; then
  if ! $PM install -y coreutils; then
    echo "ERROR: readlink isn't available."
    exit 1
  fi
fi

# Create wrapper function for downloading files based on available command
function download() {
  if [[ $rundownload == "yes" ]]; then
    $download_cmd "$1"
  fi
}

echo "---- Boostrap install Fakeroot from Debian 11 binary (GLIBC 2.31) ----"
echo " Using package manager: $PM"
echo " System $(getconf GNU_LIBC_VERSION)"
echo ""

# Apptainer in build mode can install curl, tar, xz, and ar, when using dnf.
# Note: for apt-based systems, we manually install them, because apt cannot update
# its source list without fakeroot, whereas dnf can.

if [[ $PM == "dnf" ]]; then
  if ! command -v ar >/dev/null 2>&1; then
    $PM install -y binutils
  fi

  if ! command -v tar >/dev/null 2>&1; then
    $PM install -y tar
  fi

  if ! command -v xz >/dev/null 2>&1; then
    $PM install -y xz
  fi

  mkdir -vp /opt/fakeroot-bootstrap

  # Apptainer in build mode cannot install util-linux without fakeroot, so we manually install/extract getopt first
  if ! command -v getopt >/dev/null 2>&1; then
    download http://ftp.de.debian.org/debian/pool/main/u/util-linux/util-linux_2.36.1-8+deb11u2_amd64.deb
    ar vx util-linux_2.36.1-8+deb11u2_amd64.deb data.tar.xz
    tar -xvJf data.tar.xz --no-same-owner --no-overwrite-dir -C /opt/fakeroot-bootstrap ./usr/bin/getopt
    rm -v util-linux_2.36.1-8+deb11u2_amd64.deb data.tar.xz
  fi

  # Install fakeroot and libfakeroot manually

  download http://ftp.de.debian.org/debian/pool/main/f/fakeroot/libfakeroot_1.25.3-1.1_amd64.deb
  ar vx libfakeroot_1.25.3-1.1_amd64.deb data.tar.xz
  tar -xvJf data.tar.xz --no-same-owner --no-overwrite-dir -C /opt/fakeroot-bootstrap ./usr/lib/x86_64-linux-gnu/libfakeroot/
  rm -v libfakeroot_1.25.3-1.1_amd64.deb data.tar.xz

  download http://ftp.de.debian.org/debian/pool/main/f/fakeroot/fakeroot_1.25.3-1.1_amd64.deb
  ar vx fakeroot_1.25.3-1.1_amd64.deb data.tar.xz
  tar -xvJf data.tar.xz --no-same-owner --no-overwrite-dir -C /opt/fakeroot-bootstrap ./usr/bin/
  rm -v fakeroot_1.25.3-1.1_amd64.deb data.tar.xz

else
  # For apt-based systems
  if ! command -v getopt >/dev/null 2>&1; then
    echo "-> Installing getopt"
    download http://ftp.de.debian.org/debian/pool/main/u/util-linux/util-linux_2.36.1-8+deb11u2_amd64.deb
    dpkg-deb -x util-linux_2.36.1-8+deb11u2_amd64.deb /opt/fakeroot-bootstrap
  fi

  download http://ftp.de.debian.org/debian/pool/main/f/fakeroot/libfakeroot_1.25.3-1.1_amd64.deb
  download http://ftp.de.debian.org/debian/pool/main/f/fakeroot/fakeroot_1.25.3-1.1_amd64.deb
  dpkg -x libfakeroot_1.25.3-1.1_amd64.deb /opt/fakeroot-bootstrap
  dpkg -x fakeroot_1.25.3-1.1_amd64.deb /opt/fakeroot-bootstrap

fi

export PATH="/opt/fakeroot-bootstrap/usr/bin:/opt/fakeroot-bootstrap/bin:$PATH"
export LD_LIBRARY_PATH="/opt/fakeroot-bootstrap/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
mkdir -vp /usr/lib/x86_64-linux-gnu/
cp -vr /opt/fakeroot-bootstrap/usr/lib/x86_64-linux-gnu/libfakeroot /usr/lib/x86_64-linux-gnu/.

mkdir -vp /usr/bin/
cp -v /opt/fakeroot-bootstrap/usr/bin/* /usr/bin/.

echo "-> Finalizing fakeroot installation via package manager (update first)"
FAKEROOTDONTTRYCHOWN=1 fakeroot-tcp bash -c "
  $PM update -y
  if [[ $PM == "dnf" ]] && ! grep -qi fedora /etc/os-release ; then
    $PM install -y epel-release
  fi
  $PM install -y fakeroot
"

# cleanup
rm -vrf /opt/fakeroot-bootstrap
