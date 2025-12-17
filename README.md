# fakeroot-bootstrap

A bootstrap script for installing `fakeroot` in containerised environments like Apptainer/Singularity.

Useful when you cannot bind fakeroot in from the host during a container build because of a mismatch in GLIBC versions between the container and the host.

See: https://apptainer.org/docs/user/main/fakeroot.html#using-fakeroot-command-inside-definition-file

## Usage
Download the script in the `%post` stage of an Apptainer definition file and execute it before doing any package installations that might require fakeroot e.g.

```singularity
BootStrap: docker
From: almalinux:8

%post
    # Download
    curl -#O https://raw.githubusercontent.com/dliptai/fakeroot-bootstrap/refs/heads/main/bootstrap.sh

    # Execute
    chmod +x bootstrap.sh
    ./bootstrap.sh

    # Use newly installed fakeroot to install other packages
    FAKEROOTDONTTRYCHOWN=1 fakeroot bash -c '
        dnf update -y
        dnf install -y openssh
    '
```

Remember to build with the `--ignore-fakeroot-command` command line argument
```bash
apptainer build --ignore-fakeroot-command mycontainer.sif mycontainer.def
```

Note: if your base container doesn't have `curl`, try `wget`.


### Offline mode (pre-downloaded packages)
If your container is missing both `curl` and `wget` (this is common in base Debian/Ubuntu images), you'll need to run the script in offline mode. This involves downloading the bootstrap script and also the relevant archives on the host machine, copying them in to the container in the `%files` section, and running the bootstrap script with the argument `no-download`.

On the host:
```bash
wget https://raw.githubusercontent.com/dliptai/fakeroot-bootstrap/refs/heads/main/bootstrap.sh
```

then, if your container is Debian-based
```bash
wget http://ftp.de.debian.org/debian/pool/main/u/util-linux/util-linux_2.36.1-8+deb11u2_amd64.deb
wget http://ftp.de.debian.org/debian/pool/main/f/fakeroot/libfakeroot_1.25.3-1.1_amd64.deb
wget http://ftp.de.debian.org/debian/pool/main/f/fakeroot/fakeroot_1.25.3-1.1_amd64.deb
```

or, if your container is RHEL-based
```bash
wget https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi8/8/x86_64/baseos/os/Packages/u/util-linux-2.32.1-46.el8.x86_64.rpm
wget https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/f/fakeroot-libs-1.33-1.el8.x86_64.rpm
wget https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/f/fakeroot-1.33-1.el8.x86_64.rpm
```

In the definition file
```singularity
BootStrap: docker
From: debian:11

%files
    # Copy files in from host
    bootstrap.sh
    util-linux_2.36.1-8+deb11u2_amd64.deb
    libfakeroot_1.25.3-1.1_amd64.deb
    fakeroot_1.25.3-1.1_amd64.deb

%post
    # Execute
    chmod +x bootstrap.sh
    ./bootstrap.sh no-download

    # Use newly installed fakeroot to install other packages
    FAKEROOTDONTTRYCHOWN=1 fakeroot bash -c '
        apt update -y
        apt install -y openssh-server
    '
```


## Supported Systems

- **Debian-based** distributions (using `apt`): Debian, Ubuntu, etc.
- **RHEL-based** distributions (using `dnf`): Fedora, CentOS, RHEL, etc.
- **Architecture**: x86_64 only
- **GLIBC version**: 2.14 or later (Debian 11 or EPEL 8 binaries)


## Prerequisites
The following tools are required in the container:
- Shell: `bash`
- One of: `curl`, `wget` (note that `dnf` will auto-install `curl` if your have neither)
- Package manager: `apt` or `dnf`
- Basic utilities: `readlink`


## Details
The script will:
1. Detect your package manager (apt or dnf)
2. Ensure download tools are available
3. Download binary packages from official mirrors
4. Extract and install them to your system into a temporary location
5. Use the unpacked fakeroot to install fakeroot properly via your package manager


## License
See the LICENSE file for licensing information.
