#!/bin/bash
# ===================================================
# Custom Fedora Desktop Install Script
# ===================================================
# kineticwe, noctalia, AMD, Btrfs, CachyOS, Gaming
# Includes full Snapper + grub‑btrfs integration
# ===================================================
set -e

INSTALL_ALL_USER_PKGS=false
INSTALL_CACHYOS_KERNEL=false
ASK_CACHYOS=true
INSTALL_HYPRLAND=""
AUTO_REBOOT=false
INSTALL_ALL_USER_APPS=false      # <-- new
DO_BTRFS_SETUP=""                # <-- new (true/false/empty = prompt)

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user-pkgs) INSTALL_ALL_USER_PKGS=true ;;
        --cachyos) INSTALL_CACHYOS_KERNEL=true; ASK_CACHYOS=false ;;
        --no-cachyos) INSTALL_CACHYOS_KERNEL=false; ASK_CACHYOS=false ;;
        --hyprland) INSTALL_HYPRLAND=true ;;
        --no-hyprland) INSTALL_HYPRLAND=false ;;
        --all-apps) INSTALL_ALL_USER_APPS=true ;;                 # new
        --btrfs-setup) DO_BTRFS_SETUP=true ;;                    # new
        --no-btrfs-setup) DO_BTRFS_SETUP=false ;;                # new
        --all)
            INSTALL_ALL_USER_PKGS=true
            INSTALL_CACHYOS_KERNEL=true
            ASK_CACHYOS=false
            INSTALL_HYPRLAND=true
            INSTALL_ALL_USER_APPS=true                           # new
            DO_BTRFS_SETUP=true                                  # new
            ;;
        --reboot) AUTO_REBOOT=true ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --user-pkgs    Automatically install optional user packages (Docker, KVM)"
            echo "  --cachyos      Automatically install CachyOS Kernel & Schedulers"
            echo "  --no-cachyos   Skip CachyOS Kernel installation"
            echo "  --hyprland     Install Hyprland (Wayland compositor)"
            echo "  --no-hyprland  Skip Hyprland installation"
            echo "  --all-apps     Automatically install all recommended Step 6 applications"
            echo "  --btrfs-setup  Automatically perform Btrfs snapshot & grub‑btrfs setup"
            echo "  --no-btrfs-setup  Skip Btrfs setup (manual grub update required later)"
            echo "  --all          Install all optional packages and features"
            echo "  --reboot       Automatically reboot at the end"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# 1. Auto‑elevate to root
if [ "$EUID" -ne 0 ]; then
    echo "This script requires administrative privileges."
    echo "Requesting sudo access..."
    exec sudo bash "$0" "$@"
fi

TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# 2. Error handling
handle_error() {
    echo -e "\n\e[31m[WARNING]\e[0m An error occurred during: $1"
    read -p "Do you want to ignore this and continue to the next step? (y/N): " choice
    case "$choice" in
        y|Y ) echo -e "Continuing script...\n";;
        * ) echo "Aborting script."; exit 1;;
    esac
}

echo "==================================================="
echo "  Custom Fedora Desktop Install Script"
echo "  kineticwe, noctalia, AMD, Btrfs, CachyOS, Gaming"
echo "  Target User: $TARGET_USER ($TARGET_HOME)"
echo "==================================================="

## Pre‑Installation Configuration
echo -e "\n---> Pre-Installation Configuration"

# Btrfs setup question (if not already decided via flags)
if [ -z "$DO_BTRFS_SETUP" ]; then
    read -p "Set up Btrfs snapshots, compression & grub‑btrfs? (y/N): " choice_btrfs
    if [[ "$choice_btrfs" =~ ^[Yy]$ ]]; then
        DO_BTRFS_SETUP=true
    else
        DO_BTRFS_SETUP=false
    fi
fi

## Step 1 — Optimising DNF & Enabling Repositories
echo -e "\n---> Step 1: Optimising DNF & Enabling Repositories"

# Optimise DNF
grep -q '^fastestmirror=True' /etc/dnf/dnf.conf || echo 'fastestmirror=True' >> /etc/dnf/dnf.conf
grep -q '^max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
grep -q '^defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' >> /etc/dnf/dnf.conf
grep -q '^keepcache=True' /etc/dnf/dnf.conf || echo 'keepcache=True' >> /etc/dnf/dnf.conf

# Enable COPR repositories (Hyprland COPR will be enabled later if needed)
dnf copr enable -y theblackdon/kineticwe || handle_error "Enabling kineticwe COPR"

# --- lgl-system-loadout optional ---
INSTALL_LGL=false
read -p "Install lgl-system-loadout? (system monitoring overlay) (y/N): " choice_lgl
if [[ "$choice_lgl" =~ ^[Yy]$ ]]; then
    INSTALL_LGL=true
    dnf copr enable -y linuxgamerlife/lgl-system-loadout || handle_error "Enabling lgl-system-loadout COPR"
fi

# RPM Fusion
dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
               https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
               || handle_error "Installing RPM Fusion Repositories"

dnf config-manager setopt rpmfusion-free.enabled=1 || handle_error "Setting rpmfusion-free enabled"
dnf config-manager setopt rpmfusion-free-updates.enabled=1 || handle_error "Setting rpmfusion-free-updates enabled"

## Step 2 — Desktop Environment & Core Packages
echo -e "\n---> Step 2: Desktop Environment & Core Packages"

CORE_PACKAGES="dnf-plugins-core kineticwe noctalia"
if [ "$INSTALL_LGL" = true ]; then
    CORE_PACKAGES="$CORE_PACKAGES lgl-system-loadout"
fi

dnf install -y --skip-broken $CORE_PACKAGES || handle_error "Installing Desktop Environment and Core Packages"

# Hyprland question (if not already set by flag) – moved just before installation
if [ -z "$INSTALL_HYPRLAND" ]; then
    read -p "Install Hyprland (Wayland compositor)? (y/N): " choice_hypr
    if [[ "$choice_hypr" =~ ^[Yy]$ ]]; then
        INSTALL_HYPRLAND=true
        # Enable Hyprland COPR only when user opts in
        dnf copr enable -y lionheartp/Hyprland || handle_error "Enabling Hyprland COPR"
    else
        INSTALL_HYPRLAND=false
    fi
fi

if [ "$INSTALL_HYPRLAND" = true ]; then
    echo "Installing Hyprland..."
    dnf install -y hyprland || handle_error "Installing Hyprland"
fi

# SDDM is installed regardless
dnf install -y sddm || handle_error "Installing SDDM"
systemctl set-default graphical.target || handle_error "Setting default target to graphical"
systemctl enable --force sddm.service || handle_error "Enabling SDDM Display Manager"

## Step 3 — Hardware Drivers, Codecs & Media
echo -e "\n---> Step 3: Hardware Drivers, Codecs & Media"
dnf swap -y ffmpeg-free ffmpeg --allowerasing || handle_error "Swapping to full FFmpeg"
dnf upgrade --refresh -y || handle_error "System Upgrade"
dnf distro-sync -y || handle_error "Distro Sync"

dnf install -y --skip-broken mesa-va-drivers-freeworld \
  mesa-vulkan-drivers-freeworld mesa-dri-drivers \
  vulkan-loader vulkan-tools || handle_error "Graphics"

if ! grep -q "LIBVA_DRIVER_NAME=radeonsi" "$TARGET_HOME/.bashrc"; then
    echo "export LIBVA_DRIVER_NAME=radeonsi" >> "$TARGET_HOME/.bashrc"
    chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.bashrc"
fi
dnf install -y libva-utils || handle_error "Installing libva-utils"

## Step 4 — Firewall and Virtualisation
echo -e "\n---> Step 4: Firewall and Virtualisation"

dnf install -y firewalld firewall-config || handle_error "Installing Firewalld"
systemctl enable --now firewalld || handle_error "Enabling Firewalld"

is_installed_dnf() { rpm -q "$1" &>/dev/null; }

# ===== DOCKER =====
if [ "$INSTALL_ALL_USER_PKGS" = true ]; then
  install_docker="y"
  echo "[INFO] Docker installation auto-selected."
else
  read -p "Install Docker Engine? (y/N): " install_docker
fi
if [[ "$install_docker" =~ ^[Yy]$ ]]; then
  curl -fsSL https://get.docker.com | sh || handle_error "Docker installer"
  systemctl enable --now docker
  usermod -aG docker "$TARGET_USER"
  echo "Docker installed. Added $TARGET_USER to docker group."
fi

# ===== KVM/QEMU =====
if [ "$INSTALL_ALL_USER_PKGS" = true ]; then
  install_kvm="y"
  echo "[INFO] KVM/QEMU installation auto-selected."
else
  read -p "Install KVM/QEMU Virtualization? (y/N): " install_kvm
fi
if [[ "$install_kvm" =~ ^[Yy]$ ]]; then
  dnf install -y @virtualization libvirt || handle_error "Installing virtualization group and libvirt"
  systemctl enable libvirtd
  sed -i 's/^#*firewall_backend = .*/firewall_backend = "iptables"/' /etc/libvirt/network.conf
  systemctl restart libvirtd
  virsh net-autostart default || handle_error "Autostarting default VM network"
fi

## Step 5 — Cachyos Kernel with sch-ext addons
echo -e "\n---> Step 5: Cachyos Kernel with sch-ext addons"

# Ask about CachyOS only if not already decided by a flag
if [ "$ASK_CACHYOS" = true ]; then
    read -p "Install CachyOS Kernel and Performance Schedulers? (y/N): " choice_cachy
    if [[ "$choice_cachy" =~ ^[Yy]$ ]]; then
        INSTALL_CACHYOS_KERNEL=true
    fi
fi

if [ "$INSTALL_CACHYOS_KERNEL" = true ]; then
    echo "Installing CachyOS Kernel & Tools..."
    dnf copr enable -y bieszczaders/kernel-cachyos || handle_error "Enabling CachyOS Kernel COPR"
    dnf copr enable -y bieszczaders/kernel-cachyos-addons || handle_error "Enabling CachyOS Addons COPR"
    dnf install -y --skip-broken kernel-cachyos kernel-cachyos-devel-matched libdnf5-plugin-actions \
        || handle_error "Installing CachyOS Kernel"

    mkdir -p /etc/dnf/libdnf5-plugins/actions.d
    cat << 'EOF' > /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions
# Set the latest CachyOS kernel as the default boot entry
post_transaction:kernel*:in::/usr/bin/sh -c /usr/bin/grubby\ --set-default=/boot/$(ls\ /boot\ |\ grep\ vmlinuz.*cachy\ |\ sort\ -V\ |\ tail\ -1)
EOF

    dnf remove -y zram-generator-defaults || true
    dnf swap -y zram-generator-defaults cachyos-settings || handle_error "Swapping to cachyos-settings"
    dnf install -y --skip-broken cachyos-settings scx-manager scx-scheds-git scx-tools-git || handle_error "Installing CachyOS Schedulers"
    dracut -f || handle_error "Rebuilding initramfs (dracut)"
else
    echo "[INFO] Skipping CachyOS Kernel Installation."
fi

## Step 6 — User Applications
echo -e "\n---> Step 6 User Applications"
enable_copr() { dnf repolist enabled | grep -iq "${1/\//.*}" || dnf copr enable -y "$1"; }
enable_copr "wehagy/protonplus"; enable_copr "ilyaz/LACT"; enable_copr "lihaohong/yazi"

if [ ! -f /etc/yum.repos.d/brave-browser-nightly.repo ]; then
  echo "Adding Brave repository..."
  curl -fsSL https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo -o /etc/yum.repos.d/brave-browser-nightly.repo || handle_error "Adding Brave Nightly Repository"
else
  echo "Brave repository is already added."
fi

PACKAGES=(steam mangohud gamescope protontricks protonplus goverlay lact mpv loupe gnome-calculator qbittorrent brave-origin-nightly dolphin kde-partitionmanager flatpak yazi fastfetch zsh rsync duf btop tldr htop distrobox podman)

if [ "$INSTALL_ALL_USER_APPS" = true ]; then
    echo "[INFO] --all-apps used: installing all user applications without prompts."
    INSTALL_ALL_APPS=true
else
    read -p "Do you want to install ALL recommended user applications? (Choosing 'no' will ask for each individually) (y/N): " install_all_choice
    if [[ "$install_all_choice" =~ ^[Yy]$ ]]; then
        INSTALL_ALL_APPS=true
    else
        INSTALL_ALL_APPS=false
    fi
fi

if [ "$INSTALL_ALL_APPS" = true ]; then
    echo "Installing all user applications..."
    for PKG in "${PACKAGES[@]}"; do
        if is_installed_dnf "$PKG"; then
            echo "[SKIP] $PKG (already installed)"
        else
            echo "Installing $PKG..."
            dnf install -y "$PKG" || echo "[FAIL] $PKG"
        fi
    done
else
    echo "You can now choose which applications to install."
    for PKG in "${PACKAGES[@]}"; do
        if is_installed_dnf "$PKG"; then
            echo "[SKIP] $PKG (already installed)"
            continue
        fi
        read -p "Install $PKG? [y/N]: " c
        if [[ "$c" =~ ^[Yy]$ ]]; then
            dnf install -y "$PKG" && echo "[OK] $PKG" || {
                echo "[FAIL] $PKG"
                [ "$PKG" = "brave-origin-nightly" ] && curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin CHANNEL=nightly sh
            }
        fi
    done
fi

# Zed (outside the main list)
su - "$TARGET_USER" -c "command -v zed &>/dev/null || [ -f ~/.local/bin/zed ]" || {
  read -p "Install Zed editor? [y/N]: " c
  [[ "$c" =~ ^[Yy]$ ]] && su - "$TARGET_USER" -c "curl -f https://zed.dev/install.sh | sh"
}

# Firefox removal if Brave installed
if is_installed_dnf "brave-origin-nightly" || is_installed_dnf "brave-origin"; then
  is_installed_dnf "firefox" && read -p "Remove Firefox? [y/N]: " c && [[ "$c" =~ ^[Yy]$ ]] && dnf remove -y firefox
fi

# Bazaar Flatpak installation
if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
    if [ "$INSTALL_ALL_APPS" = true ]; then
        echo "Installing Bazaar (GUI package manager) from Flathub..."
        flatpak install -y flathub io.github.kolunmi.Bazaar || echo "[FAIL] Bazaar"
    else
        read -p "Install Bazaar (Flathub) GUI package manager? [y/N]: " c
        if [[ "$c" =~ ^[Yy]$ ]]; then
            flatpak install -y flathub io.github.kolunmi.Bazaar || echo "[FAIL] Bazaar"
        fi
    fi
else
    echo "[INFO] Flatpak not installed – skipping Bazaar installation."
fi

# =================================================================
## Step 7 — Btrfs Snapshots, Compression & Snapper+grub‑btrfs Setup
# =================================================================
echo -e "\n---> Step 7: Btrfs Snapshots, Compression & System Recovery Setup"

if [ "$DO_BTRFS_SETUP" = true ]; then
    # 7.1 Required packages
    dnf install -y snapper libdnf5-plugin-actions btrfs-assistant inotify-tools make git || handle_error "Installing Btrfs tools"

    # 7.2 Snapper configs
    if [[ ! -d /.snapshots ]]; then
        snapper -c root create-config / || handle_error "Creating root Snapper config"
    fi
    if [[ ! -d /home/.snapshots ]]; then
        snapper -c home create-config /home || handle_error "Creating home Snapper config"
    fi

    REAL_USER="${TARGET_USER}"
    snapper -c root set-config ALLOW_USERS="$REAL_USER" SYNC_ACL=yes || handle_error "Setting root ACL"
    snapper -c home set-config ALLOW_USERS="$REAL_USER" SYNC_ACL=yes || handle_error "Setting home ACL"
    snapper -c home set-config TIMELINE_CREATE=no || handle_error "Disabling home timeline"

    restorecon -RFv /.snapshots  2>/dev/null || true
    restorecon -RFv /home/.snapshots 2>/dev/null || true

    # 7.3 Timeline limits for root
    sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="5"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="10"/' /etc/snapper/configs/root

    # 7.4 updatedb exclusion
    if grep -q '^PRUNENAMES' /etc/updatedb.conf; then
        grep -q '\.snapshots' /etc/updatedb.conf || \
            sed -i 's|^PRUNENAMES *= *"|PRUNENAMES = ".snapshots |' /etc/updatedb.conf
    else
        echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf
    fi

    # 7.5 grub‑btrfs
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cd "$tmpdir"
    git clone --depth 1 https://github.com/Antynea/grub-btrfs || handle_error "Cloning grub-btrfs"
    cd grub-btrfs

    sed -i \
        -e 's|^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=.*|GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"|' \
        -e 's|^#GRUB_BTRFS_GRUB_DIRNAME=.*|GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"|' \
        -e 's|^#GRUB_BTRFS_MKCONFIG=.*|GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig|' \
        -e 's|^#GRUB_BTRFS_SCRIPT_CHECK=.*|GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check|' \
        config

    make install || handle_error "Installing grub-btrfs"
    systemctl enable --now grub-btrfsd.service || handle_error "Enabling grub-btrfsd"

    echo "==> Updating GRUB configuration..."
    grub2-mkconfig -o /boot/grub2/grub.cfg || handle_error "Running grub2-mkconfig"

    cd /
    rm -rf "$tmpdir"
    trap - EXIT

    # 7.6 Snapper DNF5 integration scripts
    mkdir -p /usr/local/bin

    cat << 'SCRIPT' > /usr/local/bin/snapper-pre.sh
#!/usr/bin/env bash
set -e
PID="$1"
STATE_DIR="/run/snapper-actions"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
if [[ ! -d /usr/lib/sysimage/libdnf5 ]]; then
    mkdir -p /usr/lib/sysimage/libdnf5
    restorecon -q /usr/lib/sysimage/libdnf5 2>/dev/null || true
fi
desc=$(/usr/local/bin/snapper-desc.sh "$PID")
echo "$desc" > "$STATE_DIR/snapper_desc_${PID}"
pre=$(snapper -c root create -c number -t pre -p -d "$desc") || exit 1
echo "$pre" > "$STATE_DIR/snapper_pre_${PID}"
SCRIPT
    chmod 755 /usr/local/bin/snapper-pre.sh

    cat << 'SCRIPT' > /usr/local/bin/snapper-desc.sh
#!/usr/bin/env bash
PID="$1"
cmd=$(ps -o command --no-headers -p "$PID" 2>/dev/null || echo "Unknown Task")
case "$cmd" in
    */dnf5daemon* | */packagekitd*) echo "GUI" ;;
    *) echo "$cmd" ;;
esac
SCRIPT
    chmod 755 /usr/local/bin/snapper-desc.sh

    cat << 'SCRIPT' > /usr/local/bin/snapper-gui-pkg.sh
#!/usr/bin/env bash
PID="$1"
ACTION="$2"
NAME="$3"
STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PKG_FILE="$STATE_DIR/snapper_gui_${PID}"
desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
[[ "$desc" != "GUI" ]] && exit 0
[[ -f "$PKG_FILE" ]] && exit 0
case "$ACTION" in
    I|U|D|R) echo "GUI install ${NAME}" > "$PKG_FILE" ;;
    E|O)     echo "GUI remove ${NAME}" > "$PKG_FILE" ;;
esac
SCRIPT
    chmod 755 /usr/local/bin/snapper-gui-pkg.sh

    cat << 'SCRIPT' > /usr/local/bin/snapper-post.sh
#!/usr/bin/env bash
PID="$1"
STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PRE_FILE="$STATE_DIR/snapper_pre_${PID}"
GUI_FILE="$STATE_DIR/snapper_gui_${PID}"
desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
pre=$(cat "$PRE_FILE" 2>/dev/null || echo "")
gui_pkg=$(cat "$GUI_FILE" 2>/dev/null || echo "")
[[ -z "$pre" ]] && exit 0
if [[ -n "$gui_pkg" ]]; then
    desc="$gui_pkg"
    snapper -c root modify -d "$desc" "$pre" || true
fi
/usr/local/bin/snapper-wal-checkpoint.sh || true
snapper -c root create -c number -t post --pre-number "$pre" -d "$desc"
rm -f "$DESC_FILE" "$PRE_FILE" "$GUI_FILE"
SCRIPT
    chmod 755 /usr/local/bin/snapper-post.sh

    cat << 'SCRIPT' > /usr/local/bin/snapper-wal-checkpoint.sh
#!/usr/bin/env bash
python3 - <<'EOF'
import sqlite3, time, sys
DB = "/usr/lib/sysimage/rpm/rpmdb.sqlite"
for i in range(10):
    try:
        conn = sqlite3.connect(DB, timeout=3)
        conn.execute("PRAGMA busy_timeout=3000")
        result = conn.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        conn.close()
        if result and result[1] == 0:
            sys.exit(0)
    except sqlite3.OperationalError:
        pass
    time.sleep(0.5)
sys.exit(1)
EOF
SCRIPT
    chmod 755 /usr/local/bin/snapper-wal-checkpoint.sh

    mkdir -p /etc/dnf/libdnf5-plugins/actions.d
    cat << 'CONFIG' > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
# Snapper integration with libdnf5 (DNF5 transactions)
pre_transaction::::/usr/local/bin/snapper-pre.sh ${pid}pre_transaction:*:in::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}pre_transaction:*:out::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}post_transaction::::/usr/local/bin/snapper-post.sh ${pid}
CONFIG

    restorecon -v /usr/local/bin/snapper-*.sh 2>/dev/null || true

    # 7.7 Enable Snapper timers
    systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || handle_error "Enabling Snapper timers"

    # 7.8 Btrfs compression
    echo "Enabling Btrfs compression (zstd:1) in /etc/fstab..."
    if grep -q "btrfs" /etc/fstab; then
        cp /etc/fstab /etc/fstab.bkp.$(date +%Y%m%d_%H%M%S)
        sed -i '/ btrfs / s/subvol=[^ ,]*/&,compress=zstd:1/' /etc/fstab
        echo "[INFO] Btrfs compression enabled. Original fstab backed up."
    else
        echo "[WARNING] No btrfs entries found in /etc/fstab. Skipping compression setup."
    fi
else
    echo "[INFO] Btrfs snapshot setup skipped (--no-btrfs-setup or declined)."
fi

# ===================================================
# Final messages & reboot
# ===================================================
echo -e "\n==================================================="
echo " INSTALLATION COMPLETE "
echo "==================================================="
echo "⚠️ MANUAL CONFIGURATIONS REQUIRED ⚠️"
echo "---------------------------------------------------"
if [ "$DO_BTRFS_SETUP" != false ]; then
echo " 1. GRUB has already been updated with snapshot entries."
fi

if [ "$DO_BTRFS_SETUP" != true ]; then
echo " 1. Btrfs snapshots were NOT set up. If you configure them later,"
echo " run:  grub2-mkconfig -o /boot/grub2/grub.cfg"
echo ""
fi

echo ""
echo " 2. Log in via SDDM allows:"
if [ "$INSTALL_HYPRLAND" = true ]; then
    echo "    - Choose Hyprland (Wayland) or Kineticwe (KDE) sessions."
else
    echo "    - Hyprland not installed; only Kineticwe (KDE) is available."
fi
echo "    - For Noctalia, enable Polkit in Security settings."
echo ""
echo " 3. In KDE System Settings:"
echo "    - Disable File Search, Plasma Search, and KRunner History."
echo ""
if [ "$DO_BTRFS_SETUP" = true ]; then
    echo " 4. Snapper is fully integrated (no extra steps required)."
else
    echo " 4. Snapper was NOT installed. To enable automatic snapshots, refer to"
    echo "    Snapper documentation and remember to update GRUB afterwards."
fi
echo "==================================================="

echo -e "\nSystem changes require a reboot to take effect."

if [ "$AUTO_REBOOT" = true ]; then
    echo "[INFO] Auto-reboot selected. Rebooting in 5 seconds..."
    sleep 5
    reboot
else
    read -p "Would you like to reboot the system now? (y/n): " do_reboot
    if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
        echo "Rebooting system..."
        reboot
    else
        echo "Reboot cancelled. Please remember to manually run 'sudo reboot' later."
    fi
fi
