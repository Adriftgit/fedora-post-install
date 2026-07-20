#!/bin/bash
# ===================================================
# Custom Fedora Desktop Install Script
# kineticwe, noctalia, AMD, Btrfs, CachyOS, Gaming
# Includes full Snapper + grub-btrfs integration
# ===================================================
set -e

# ---- Parse command-line options ----
INSTALL_ALL_USER_PKGS=false
INSTALL_CACHYOS_KERNEL=false
ASK_CACHYOS=true
AUTO_REBOOT=false
INSTALL_SDDM=""
INSTALL_FIREWALLD=""
INSTALL_DNF_OPTIMIZE=""
INSTALL_GRAPHICS_DRIVERS=""
INSTALL_FFMPEG_LIBS=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cachyos) INSTALL_CACHYOS_KERNEL=true; ASK_CACHYOS=false ;;
        --no-cachyos) INSTALL_CACHYOS_KERNEL=false; ASK_CACHYOS=false ;;
        --sddm) INSTALL_SDDM=true ;;
        --no-sddm) INSTALL_SDDM=false ;;
        --ffmpeg-libs) INSTALL_FFMPEG_LIBS=true ;;
        --no-ffmpeg-libs) INSTALL_FFMPEG_LIBS=false ;;
        --all)
            INSTALL_ALL_USER_PKGS=true
            INSTALL_CACHYOS_KERNEL=true
            ASK_CACHYOS=false
            INSTALL_SDDM=true
            INSTALL_FIREWALLD=true
            INSTALL_DNF_OPTIMIZE=true
            INSTALL_GRAPHICS_DRIVERS=true
            INSTALL_FFMPEG_LIBS=true
            ;;
        --reboot) AUTO_REBOOT=true ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --user-pkgs       Auto-install optional packages (Docker, KVM)"
            echo "  --cachyos         Auto-install CachyOS Kernel & Schedulers"
            echo "  --no-cachyos      Skip CachyOS Kernel"
            echo "  --sddm            Install SDDM display manager"
            echo "  --no-sddm         Skip SDDM"
            echo "  --ffmpeg-libs     Install ffmpeg-libs, libva, libva-utils"
            echo "  --no-ffmpeg-libs  Skip ffmpeg-libs"
            echo "  --all             Install all optional features"
            echo "  --reboot          Automatically reboot after completion"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# ---- Auto-elevate to root ----
if [ "$EUID" -ne 0 ]; then
    echo "Requesting sudo access..."
    exec sudo bash "$0" "$@"
fi

TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# ---- Error handler ----
handle_error() {
    echo -e "\n\e[31m[WARNING]\e[0m An error occurred during: $1"
    read -p "Ignore and continue? (y/N): " choice
    [[ "$choice" =~ ^[Yy]$ ]] && return || exit 1
}

# ---- Helper functions ----
is_installed_dnf() { 
    rpm -q "$1" &>/dev/null
}

enable_copr() { 
    dnf repolist enabled | grep -iq "${1/\//.*}" || dnf copr enable -y "$1"
}

confirm() { 
    # usage: confirm "Question? (Y/n)" default=Y
    local prompt="$1" default="${2:-Y}"
    if [[ "$default" =~ ^[Yy]$ ]]; then
        read -p "$prompt " choice
        [[ ! "$choice" =~ ^[Nn]$ ]]
    else
        read -p "$prompt " choice
        [[ "$choice" =~ ^[Yy]$ ]]
    fi
}

echo "==================================================="
echo "  Custom Fedora Desktop Install Script"
echo "  Target User: $TARGET_USER ($TARGET_HOME)"
echo "==================================================="

# ===== Step 1 — DNF Optimisations, Network Tweak, Repos =====
echo -e "\n---> Step 1: DNF Optimisations & Repositories"
if [ -z "$INSTALL_DNF_OPTIMIZE" ]; then
    confirm "Apply DNF optimizations? (fastestmirror, parallel downloads, etc.) (Y/n)" && INSTALL_DNF_OPTIMIZE=true || INSTALL_DNF_OPTIMIZE=false
fi

if [ "$INSTALL_DNF_OPTIMIZE" = true ]; then
    grep -q '^fastestmirror=True' /etc/dnf/dnf.conf || echo 'fastestmirror=True' >> /etc/dnf/dnf.conf
    grep -q '^max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
    grep -q '^defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' >> /etc/dnf/dnf.conf
    grep -q '^keepcache=True' /etc/dnf/dnf.conf || echo 'keepcache=True' >> /etc/dnf/dnf.conf
else
    echo "[SKIP] DNF optimizations"
fi

read -p "Disable NetworkManager-wait-online.service to speed up boot? (y/N): " choice_nmwait
if [[ "$choice_nmwait" =~ ^[Yy]$ ]]; then
    systemctl disable NetworkManager-wait-online.service || echo "[WARNING] Could not disable"
else
    echo "[SKIP] NetworkManager-wait-online not disabled"
fi

echo -e "\n---> Step 1b: Enabling Repositories"
dnf copr enable -y theblackdon/kineticwe || handle_error "Enabling kineticwe COPR"
dnf copr enable -y lionheartp/Hyprland || handle_error "Enabling Hyprland COPR"

INSTALL_LGL=false
if confirm "Install lgl-system-loadout? (system monitoring overlay) (y/N)" "N"; then
    INSTALL_LGL=true
    dnf copr enable -y linuxgamerlife/lgl-system-loadout || handle_error "Enabling lgl-system-loadout COPR"
fi

dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    || handle_error "Installing RPM Fusion"

dnf config-manager setopt "rpmfusion-free.enabled=1" || handle_error "rpmfusion-free"
dnf config-manager setopt "rpmfusion-free-updates.enabled=1" || handle_error "rpmfusion-free-updates"

# ===== Step 2 — Desktop Environment & Core Packages =====
echo -e "\n---> Step 2: Desktop Environment & Core Packages"
CORE_PACKAGES="dnf-plugins-core kineticwe noctalia-git"
[ "$INSTALL_LGL" = true ] && CORE_PACKAGES="$CORE_PACKAGES lgl-system-loadout"

dnf install -y --skip-broken $CORE_PACKAGES || handle_error "Installing Core Packages"

if [ -z "$INSTALL_SDDM" ]; then
    confirm "Install SDDM display manager? (Y/n)" && INSTALL_SDDM=true || INSTALL_SDDM=false
fi

if [ "$INSTALL_SDDM" = true ]; then
    dnf install -y sddm || handle_error "Installing SDDM"
    systemctl set-default graphical.target || handle_error "Setting graphical target"
    systemctl enable sddm.service --force || handle_error "Enabling SDDM"
else
    echo "Skipping SDDM. You can start the desktop later with: start-kineticwe"
fi

# ===== Step 3 — Hardware Drivers, Codecs & Media =====
echo -e "\n---> Step 3: Hardware Drivers, Codecs & Media"
[ -z "$INSTALL_FFMPEG_LIBS" ] && confirm "Install multimedia codecs (ffmpeg-libs, libva, libva-utils)? (Y/n)" && INSTALL_FFMPEG_LIBS=true || INSTALL_FFMPEG_LIBS=false
[ -z "$INSTALL_GRAPHICS_DRIVERS" ] && confirm "Install AMD graphics drivers and Vulkan support? (Y/n)" && INSTALL_GRAPHICS_DRIVERS=true || INSTALL_GRAPHICS_DRIVERS=false

if [ "$INSTALL_GRAPHICS_DRIVERS" = true ] || [ "$INSTALL_FFMPEG_LIBS" = true ]; then
    echo "Installing selected hardware & multimedia packages..."
    [ "$INSTALL_GRAPHICS_DRIVERS" = true ] && dnf install -y mesa-va-drivers-freeworld --allowerasing || handle_error "freeworld mesa"
    [ "$INSTALL_FFMPEG_LIBS" = true ] && dnf install -y ffmpeg-libs libva libva-utils || handle_error "ffmpeg/libs"
    [ "$INSTALL_GRAPHICS_DRIVERS" = true ] && dnf install -y --skip-broken mesa-dri-drivers vulkan-loader vulkan-tools libva-utils || handle_error "AMD/Vulkan"
    
    if [ "$INSTALL_GRAPHICS_DRIVERS" = true ] && ! grep -q "LIBVA_DRIVER_NAME=radeonsi" "$TARGET_HOME/.bashrc"; then
        echo "export LIBVA_DRIVER_NAME=radeonsi" >> "$TARGET_HOME/.bashrc"
        chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.bashrc"
    fi
else
    echo "[SKIP] No hardware drivers or codecs selected"
fi

# ===== Step 4 — Firewall and Virtualisation =====
echo -e "\n---> Step 4: Firewall and Virtualisation"
[ -z "$INSTALL_FIREWALLD" ] && confirm "Install Firewalld and GUI (firewall-config)? (Y/n)" && INSTALL_FIREWALLD=true || INSTALL_FIREWALLD=false

if [ "$INSTALL_FIREWALLD" = true ]; then
    dnf install -y firewalld firewall-config || handle_error "Firewalld"
    systemctl enable --now firewalld || handle_error "Enabling firewalld"
else
    echo "[SKIP] Firewalld"
fi

# Docker
if [ "$INSTALL_ALL_USER_PKGS" = true ]; then
    install_docker="y"
    echo "[INFO] Docker auto-selected"
else
    read -p "Install Docker Engine? (y/N): " install_docker
fi

if [[ "$install_docker" =~ ^[Yy]$ ]]; then
    curl -fsSL https://get.docker.com | sh || handle_error "Docker installer"
    systemctl enable --now docker || handle_error "Enabling docker"
    usermod -aG docker "$TARGET_USER" || handle_error "Adding user to docker group"
fi

# KVM/QEMU
if [ "$INSTALL_ALL_USER_PKGS" = true ]; then
    install_kvm="y"
    echo "[INFO] KVM/QEMU auto-selected"
else
    read -p "Install KVM/QEMU Virtualization? (y/N): " install_kvm
fi

if [[ "$install_kvm" =~ ^[Yy]$ ]]; then
    dnf install -y @virtualization libvirt || handle_error "virtualization group"
    [ -f /etc/libvirt/network.conf ] && sed -i 's/^#*firewall_backend = .*/firewall_backend = "iptables"/' /etc/libvirt/network.conf
    systemctl enable --now libvirtd || handle_error "libvirtd"
    sleep 2 # Give daemon time to start before autostarting net
    virsh net-autostart default || echo "[WARNING] Could not autostart default network"
fi

# ===== Step 5 — CachyOS Kernel =====
echo -e "\n---> Step 5: CachyOS Kernel with addons"
if [ "$ASK_CACHYOS" = true ]; then
    read -p "Install CachyOS Kernel and Performance Schedulers? (y/N): " choice_cachy
    [[ "$choice_cachy" =~ ^[Yy]$ ]] && INSTALL_CACHYOS_KERNEL=true || INSTALL_CACHYOS_KERNEL=false
fi

if [ "$INSTALL_CACHYOS_KERNEL" = true ]; then
    dnf copr enable -y bieszczaders/kernel-cachyos || handle_error "CachyOS kernel COPR"
    dnf copr enable -y bieszczaders/kernel-cachyos-addons || handle_error "CachyOS addons COPR"
    dnf install -y --skip-broken kernel-cachyos kernel-cachyos-devel-matched libdnf5-plugin-actions || handle_error "CachyOS kernel"
    
    mkdir -p /etc/dnf/libdnf5-plugins/actions.d
    cat << 'EOF' > /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions
# Set the latest CachyOS kernel as the default boot entry
post_transaction:kernel*:in::/usr/bin/sh -c "/usr/bin/grubby --set-default=/boot/\$(ls /boot | grep vmlinuz.*cachy | sort -V | tail -1)"
EOF

    dnf remove -y zram-generator-defaults || true
    dnf swap -y zram-generator-defaults cachyos-settings || handle_error "swapping cachyos-settings"
    dnf install -y --skip-broken cachyos-settings scx-scheds-git scx-tools-git || handle_error "CachyOS schedulers"
else
    echo "[INFO] Skipping CachyOS Kernel"
fi

# ===== Step 6 — User Packages =====
echo -e "\n---> Step 6: User Applications"

# Helper: enable a COPR repo only if not already present
enable_copr_if_needed() {
    local copr="$1"
    if ! dnf repolist | grep -q "$copr"; then
        enable_copr "$copr"
    fi
}

# Helper: add Brave nightly repo if missing
add_brave_repo() {
    [ -f /etc/yum.repos.d/brave-browser-nightly.repo ] && return
    dnf install -y dnf-plugins-core || handle_error "dnf-plugins-core"
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo || handle_error "Brave repo"
}

# --------- Group 1: Core Apps ---------
echo -e "\n--- Group 1: Core Apps (dolphin, kitty, flatpak, zed, Brave, Bazaar) ---"
read -p "Install ALL Core Apps? (y/N): " install_all_group1
group1_packages=("dolphin" "kitty" "flatpak" "zed" "brave-origin-nightly" "bazaar")
if [[ "$install_all_group1" =~ ^[Yy]$ ]]; then
    add_brave_repo
    dnf install -y dolphin kitty flatpak brave-origin-nightly || handle_error "Group 1 dnf"
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
    flatpak install -y flathub dev.zed.Zed || echo "[FAIL] Zed"
    flatpak install -y flathub io.github.kolunmi.Bazaar || handle_error "Bazaar"
else
    for PKG in "${group1_packages[@]}"; do
        case "$PKG" in
            zed|bazaar)
                command -v flatpak &>/dev/null || { echo "[SKIP] $PKG requires Flatpak"; continue; }
                flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
                flatpak_ref="dev.zed.Zed"; [[ "$PKG" == "bazaar" ]] && flatpak_ref="io.github.kolunmi.Bazaar"
                flatpak list 2>/dev/null | grep -q "$flatpak_ref" && { echo "[SKIP] $PKG (already installed)"; continue; }
                read -p "Install $PKG (Flatpak)? [y/N]: " c
                [[ "$c" =~ ^[Yy]$ ]] && flatpak install -y flathub "$flatpak_ref" || echo "[FAIL] $PKG"
                ;;
            *)
                is_installed_dnf "$PKG" && { echo "[SKIP] $PKG (already installed)"; continue; }
                read -p "Install $PKG? [y/N]: " c
                if [[ "$c" =~ ^[Yy]$ ]]; then
                    [[ "$PKG" == "brave-origin-nightly" ]] && add_brave_repo
                    dnf install -y "$PKG" || echo "[FAIL] $PKG"
                else
                    echo "[FAIL] $PKG"
                fi
                ;;
        esac
    done
fi

# --------- Group 2: Utility Apps ---------
echo -e "\n--- Group 2: Utility Apps ---"
group2_packages=("lact" "mpv" "loupe" "gnome-calculator" "qbittorrent" "kde-partitionmanager" "yazi" "fastfetch" "zsh" "rsync" "duf" "btop" "tldr" "htop" "distrobox" "podman" "starship")
read -p "Install ALL Utility apps? (y/N): " install_all_group2
if [[ "$install_all_group2" =~ ^[Yy]$ ]]; then
    enable_copr_if_needed "ilyaz/LACT"
    enable_copr_if_needed "lihaohong/yazi"
    enable_copr_if_needed "atim/starship"
    dnf install -y --skip-broken "${group2_packages[@]}" || handle_error "Group 2 packages"
else
    for PKG in "${group2_packages[@]}"; do
        is_installed_dnf "$PKG" && { echo "[SKIP] $PKG (already installed)"; continue; }
        read -p "Install $PKG? [y/N]: " c
        if [[ "$c" =~ ^[Yy]$ ]]; then
            case "$PKG" in
                lact) enable_copr_if_needed "ilyaz/LACT" ;;
                yazi) enable_copr_if_needed "lihaohong/yazi" ;;
                starship) enable_copr_if_needed "atim/starship" ;;
            esac
            dnf install -y "$PKG" || echo "[FAIL] $PKG"
        else
            echo "[FAIL] $PKG"
        fi
    done
fi

# --------- Group 3: Gaming Apps ---------
echo -e "\n--- Group 3: Gaming Apps ---"
group3_packages=("steam" "mangohud" "gamescope" "protontricks" "protonplus" "goverlay")
read -p "Install ALL Gaming apps? (y/N): " install_all_group3
if [[ "$install_all_group3" =~ ^[Yy]$ ]]; then
    enable_copr_if_needed "wehagy/protonplus"
    dnf install -y --skip-broken "${group3_packages[@]}" || handle_error "Group 3 packages"
else
    for PKG in "${group3_packages[@]}"; do
        is_installed_dnf "$PKG" && { echo "[SKIP] $PKG (already installed)"; continue; }
        read -p "Install $PKG? [y/N]: " c
        if [[ "$c" =~ ^[Yy]$ ]]; then
            [[ "$PKG" == "protonplus" ]] && enable_copr_if_needed "wehagy/protonplus"
            dnf install -y "$PKG" || echo "[FAIL] $PKG"
        else
            echo "[FAIL] $PKG"
        fi
    done
fi

# Apply Starship preset if installed
if command -v starship &>/dev/null; then
    echo "Applying Starship preset (gruvbox-rainbow)..."
    sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config"
    sudo -u "$TARGET_USER" starship preset gruvbox-rainbow -o "$TARGET_HOME/.config/starship.toml" || \
        echo "[WARNING] Could not apply Starship preset"
fi

# Firefox removal if Brave installed
if is_installed_dnf "brave-origin-nightly" || is_installed_dnf "brave-origin"; then
    if is_installed_dnf "firefox"; then
        read -p "Remove Firefox? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && dnf remove -y firefox || echo "[WARNING] Could not remove Firefox"
    fi
fi

# ===== Step 7 — Snapper & Btrfs snapshot integration (unchanged) =====
echo -e "\n---> Step 7: Snapper & Btrfs snapshot integration"

INSTALL_SNAPPER=false
read -p "Set up Snapper & grub-btrfs for automatic snapshots on DNF transactions? (y/N): " install_snapper
if [[ ! "$install_snapper" =~ ^[Yy]$ ]]; then
    echo "[SKIP] Snapper integration not installed."
else
    INSTALL_SNAPPER=true
fi

if [ "$INSTALL_SNAPPER" = true ]; then
    if ! findmnt -n -o FSTYPE / | grep -q btrfs; then
        echo "[WARNING] Root filesystem is not Btrfs – Snapper integration cannot be set up. Skipping."
        INSTALL_SNAPPER=false
    else
        echo "Installing Snapper and dependencies..."
        dnf install -y snapper libdnf5-plugin-actions btrfs-assistant inotify-tools make git python3 \
            || handle_error "Snapper packages"

        [ -d /.snapshots ] || snapper -c root create-config / || handle_error "root snapper config"
        [ -d /home/.snapshots ] || snapper -c home create-config /home || handle_error "home snapper config"

        restorecon -RFv /.snapshots 2>/dev/null || true
        restorecon -RFv /home/.snapshots 2>/dev/null || true

        snapper -c root set-config ALLOW_USERS="$TARGET_USER" SYNC_ACL=yes || handle_error "root ACL"
        snapper -c home set-config ALLOW_USERS="$TARGET_USER" SYNC_ACL=yes || handle_error "home ACL"
        snapper -c home set-config TIMELINE_CREATE=no || handle_error "home timeline off"

        echo "Updating locate database configuration..."
        if grep -q '^PRUNENAMES' /etc/updatedb.conf; then
            grep -q '\.snapshots' /etc/updatedb.conf || \
                sed -i 's|^PRUNENAMES *= *"|PRUNENAMES = ".snapshots |' /etc/updatedb.conf
        else
            echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf
        fi

        echo "Building and installing grub-btrfs..."
        TMP_GRUB=$(mktemp -d)
        cd "$TMP_GRUB"
        git clone --depth 1 https://github.com/Antynea/grub-btrfs || handle_error "grub-btrfs clone"
        cd grub-btrfs
        sed -i \
            -e 's|^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=.*|GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"|' \
            -e 's|^#GRUB_BTRFS_GRUB_DIRNAME=.*|GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"|' \
            -e 's|^#GRUB_BTRFS_MKCONFIG=.*|GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig|' \
            -e 's|^#GRUB_BTRFS_SCRIPT_CHECK=.*|GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check|' \
            config
        make install || handle_error "grub-btrfs make install"
        systemctl enable --now grub-btrfsd.service || handle_error "grub-btrfsd service"

        echo "Regenerating GRUB configuration..."
        grub2-mkconfig -o /boot/grub2/grub.cfg || handle_error "grub2-mkconfig"

        echo "Installing DNF5 Snapper integration scripts..."

        cat > /usr/local/bin/snapper-desc.sh << 'DESCSCRIPT'
#!/bin/bash
PID="$1"
cmd=$(ps -o command --no-headers -p "$PID" 2>/dev/null || echo "Unknown Task")
case "$cmd" in
    */dnf5daemon* | */packagekitd*)
        echo "GUI"
        ;;
    *)
        echo "$cmd"
        ;;
esac
DESCSCRIPT
        chmod 755 /usr/local/bin/snapper-desc.sh

        cat > /usr/local/bin/snapper-gui-pkg.sh << 'GUIPKGSCRIPT'
#!/bin/bash
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
GUIPKGSCRIPT
        chmod 755 /usr/local/bin/snapper-gui-pkg.sh

        cat > /usr/local/bin/snapper-pre.sh << 'PRESCRIPT'
#!/bin/bash
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
PRESCRIPT
        chmod 755 /usr/local/bin/snapper-pre.sh

        cat > /usr/local/bin/snapper-post.sh << 'POSTSCRIPT'
#!/bin/bash
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
POSTSCRIPT
        chmod 755 /usr/local/bin/snapper-post.sh

        cat > /usr/local/bin/snapper-wal-checkpoint.sh << 'WALSCRIPT'
#!/bin/bash
python3 - << 'EOF'
import sqlite3
import sys
import time

DB = "/usr/lib/sysimage/rpm/rpm.sqlite"
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
WALSCRIPT
        chmod 755 /usr/local/bin/snapper-wal-checkpoint.sh

        restorecon -v /usr/local/bin/snapper-*.sh 2>/dev/null || true

        mkdir -p /etc/dnf/libdnf5-plugins/actions.d
        cat > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions << 'ACTIONS'
# Snapper pre/post snapshots for DNF5
pre_transaction::::/usr/local/bin/snapper-pre.sh ${pid}
pre_transaction:*:in::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}
pre_transaction:*:out::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}
post_transaction::::/usr/local/bin/snapper-post.sh ${pid}
ACTIONS

        systemctl enable --now snapper-timeline.timer || handle_error "snapper-timeline.timer"
        systemctl enable --now snapper-cleanup.timer || handle_error "snapper-cleanup.timer"

        echo "Snapper integration completed."
    fi
fi

# Full system update
dnf upgrade --refresh -y || handle_error "System Upgrade"
dnf distro-sync -y || handle_error "Distro Sync"

# ===================================================
# Final messages & reboot
# ===================================================
echo -e "\n==================================================="
echo " INSTALLATION COMPLETE "
echo "==================================================="
echo "MANUAL CONFIGURATIONS REQUIRED"
echo "---------------------------------------------------"
if [ "$INSTALL_SDDM" = true ]; then
    echo " 1. SDDM is installed and enabled. Choose Kineticwe (KDE) session at login."
else
    echo " 1. SDDM was NOT installed. To start desktop from TTY:"
    echo "    - After logging in, run: start-kineticwe"
fi
echo "    - For Noctalia, enable Polkit in Security settings."
echo ""
echo " 2. In KDE System Settings go to search section:"
echo "    - Disable File Search, Plasma Search, and KRunner History."

if findmnt -n -o FSTYPE / | grep -q btrfs; then
    if [ "$INSTALL_SNAPPER" = false ]; then
        echo ""
        echo " 3. Snapper & grub-btrfs integration was skipped."
        echo "    - Update GRUB with:"
        echo "      sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    fi
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
