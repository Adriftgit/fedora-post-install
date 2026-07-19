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
AUTO_REBOOT=false
INSTALL_SDDM=""
# --- Optional blocks added ---
INSTALL_FIREWALLD=""
INSTALL_DNF_OPTIMIZE=""
INSTALL_GRAPHICS_DRIVERS=""
INSTALL_FFMPEG_FULL=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user-pkgs) INSTALL_ALL_USER_PKGS=true ;;
        --cachyos) INSTALL_CACHYOS_KERNEL=true; ASK_CACHYOS=false ;;
        --no-cachyos) INSTALL_CACHYOS_KERNEL=false; ASK_CACHYOS=false ;;
        --sddm) INSTALL_SDDM=true ;;
        --no-sddm) INSTALL_SDDM=false ;;
        --ffmpeg-full) INSTALL_FFMPEG_FULL=true ;;
        --no-ffmpeg-full) INSTALL_FFMPEG_FULL=false ;;
        --all)
            INSTALL_ALL_USER_PKGS=true
            INSTALL_CACHYOS_KERNEL=true
            ASK_CACHYOS=false
            INSTALL_SDDM=true
            INSTALL_FIREWALLD=true
            INSTALL_DNF_OPTIMIZE=true
            INSTALL_GRAPHICS_DRIVERS=true
            INSTALL_FFMPEG_FULL=true
            ;;
        --reboot) AUTO_REBOOT=true ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --user-pkgs    Automatically install optional user packages (Docker, KVM)"
            echo "  --cachyos      Automatically install CachyOS Kernel & Schedulers"
            echo "  --no-cachyos   Skip CachyOS Kernel installation"
            echo "  --sddm         Install SDDM display manager"
            echo "  --no-sddm      Skip SDDM installation (manual start with start-kineticwe)"
            echo "  --ffmpeg-full  Replace ffmpeg-free with full ffmpeg"
            echo "  --no-ffmpeg-full Skip ffmpeg replacement"
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
echo "  kineticwe, noctalia, AMD, CachyOS, Gaming"
echo "  Target User: $TARGET_USER ($TARGET_HOME)"
echo "==================================================="

## Step 1 — Optimising DNF & Enabling Repositories
echo -e "\n---> Step 1: Optimising DNF & Enabling Repositories"

# DNF optimisations optional
if [ -z "$INSTALL_DNF_OPTIMIZE" ]; then
    read -p "Apply DNF optimizations? (fastestmirror, parallel downloads, etc.) (Y/n): " choice_dnf
    if [[ "$choice_dnf" =~ ^[Nn]$ ]]; then
        INSTALL_DNF_OPTIMIZE=false
    else
        INSTALL_DNF_OPTIMIZE=true
    fi
fi

if [ "$INSTALL_DNF_OPTIMIZE" = true ]; then
    grep -q '^fastestmirror=True' /etc/dnf/dnf.conf || echo 'fastestmirror=True' >> /etc/dnf/dnf.conf
    grep -q '^max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
    grep -q '^defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' >> /etc/dnf/dnf.conf
    grep -q '^keepcache=True' /etc/dnf/dnf.conf || echo 'keepcache=True' >> /etc/dnf/dnf.conf
else
    echo "[SKIP] DNF optimizations not applied."
fi

# Enable COPR repositories
dnf copr enable -y theblackdon/kineticwe || handle_error "Enabling kineticwe COPR"
dnf copr enable -y lionheartp/Hyprland || handle_error "Enabling Hyprland COPR (required by noctalia)"

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

# SDDM (display manager) – optional
if [ -z "$INSTALL_SDDM" ]; then
    read -p "Install SDDM display manager? (Y/n): " choice_sddm
    if [[ "$choice_sddm" =~ ^[Nn]$ ]]; then
        INSTALL_SDDM=false
    else
        INSTALL_SDDM=true
    fi
fi

if [ "$INSTALL_SDDM" = true ]; then
    echo "Installing SDDM..."
    dnf install -y sddm || handle_error "Installing SDDM"
    systemctl set-default graphical.target || handle_error "Setting default target to graphical"
    systemctl enable --force sddm.service || handle_error "Enabling SDDM Display Manager"
else
    echo "Skipping SDDM installation."
    echo "You can start the Kineticwe desktop manually after login with: start-kineticwe"
fi

## Step 3 — Hardware Drivers, Codecs & Media
echo -e "\n---> Step 3: Hardware Drivers, Codecs & Media"

# Full FFmpeg swap – optional
if [ -z "$INSTALL_FFMPEG_FULL" ]; then
    read -p "Replace ffmpeg-free with full ffmpeg? (Y/n): " choice_ffmpeg
    if [[ "$choice_ffmpeg" =~ ^[Nn]$ ]]; then
        INSTALL_FFMPEG_FULL=false
    else
        INSTALL_FFMPEG_FULL=true
    fi
fi

if [ "$INSTALL_FFMPEG_FULL" = true ]; then
    dnf swap -y ffmpeg-free ffmpeg --allowerasing || handle_error "Swapping to full FFmpeg"
else
    echo "[SKIP] Keeping current ffmpeg version."
fi

dnf upgrade --refresh -y || handle_error "System Upgrade"
dnf distro-sync -y || handle_error "Distro Sync"

# Graphics drivers and Vulkan optional
if [ -z "$INSTALL_GRAPHICS_DRIVERS" ]; then
    read -p "Install AMD graphics drivers and Vulkan support? (Y/n): " choice_gfx
    if [[ "$choice_gfx" =~ ^[Nn]$ ]]; then
        INSTALL_GRAPHICS_DRIVERS=false
    else
        INSTALL_GRAPHICS_DRIVERS=true
    fi
fi

if [ "$INSTALL_GRAPHICS_DRIVERS" = true ]; then
    echo "Installing graphics drivers..."

    # Install freeworld drivers, replacing stock if present
    dnf install -y mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld --allowerasing \
        || handle_error "Installing freeworld mesa drivers"

    # Install remaining graphics components
    dnf install -y --skip-broken mesa-dri-drivers vulkan-loader vulkan-tools || handle_error "Graphics"
    dnf install -y libva-utils || handle_error "Installing libva-utils"

    if ! grep -q "LIBVA_DRIVER_NAME=radeonsi" "$TARGET_HOME/.bashrc"; then
        echo "export LIBVA_DRIVER_NAME=radeonsi" >> "$TARGET_HOME/.bashrc"
        chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.bashrc"
    fi
else
    echo "[SKIP] AMD graphics drivers and Vulkan support not installed."
fi

## Step 4 — Firewall and Virtualisation
echo -e "\n---> Step 4: Firewall and Virtualisation"

# Firewalld optional
if [ -z "$INSTALL_FIREWALLD" ]; then
    read -p "Install Firewalld and GUI (firewall-config)? (Y/n): " choice_fw
    if [[ "$choice_fw" =~ ^[Nn]$ ]]; then
        INSTALL_FIREWALLD=false
    else
        INSTALL_FIREWALLD=true
    fi
fi

if [ "$INSTALL_FIREWALLD" = true ]; then
    dnf install -y firewalld firewall-config || handle_error "Installing Firewalld"
    systemctl enable --now firewalld || handle_error "Enabling Firewalld"
else
    echo "[SKIP] Firewalld not installed."
fi

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
  systemctl enable --now docker || handle_error "Enabling Docker service"
  usermod -aG docker "$TARGET_USER" || handle_error "Adding user to docker group"
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
  # Only modify config if the file exists (libvirt installed successfully)
  if [ -f /etc/libvirt/network.conf ]; then
      sed -i 's/^#*firewall_backend = .*/firewall_backend = "iptables"/' /etc/libvirt/network.conf
  fi
  systemctl enable --now libvirtd || handle_error "Enabling libvirtd"
  virsh net-autostart default || echo "[WARNING] Could not autostart default VM network"
fi

## Step 5 — Cachyos Kernel with sch-ext addons
echo -e "\n---> Step 5: Cachyos Kernel with addons"

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
post_transaction:kernel*:in::/usr/bin/sh -c "/usr/bin/grubby --set-default=/boot/\$(ls /boot | grep vmlinuz.*cachy | sort -V | tail -1)"
EOF

    dnf remove -y zram-generator-defaults || true
    dnf swap -y zram-generator-defaults cachyos-settings || handle_error "Swapping to cachyos-settings"
    dnf install -y --skip-broken cachyos-settings scx-scheds-git scx-tools-git || handle_error "Installing CachyOS Schedulers"
    # Fedora's kernel-install already handles initramfs generation – no manual dracut needed
else
    echo "[INFO] Skipping CachyOS Kernel Installation."
fi

## Step 6 — User Applications
echo -e "\n---> Step 6: User Applications"

# Helper to enable copr
enable_copr() { dnf repolist enabled | grep -iq "${1/\//.*}" || dnf copr enable -y "$1"; }
enable_copr "wehagy/protonplus"
enable_copr "ilyaz/LACT"
enable_copr "lihaohong/yazi"

# Brave repository
if [ ! -f /etc/yum.repos.d/brave-browser-nightly.repo ]; then
  echo "Adding Brave repository..."
  curl -fsSL https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo -o /etc/yum.repos.d/brave-browser-nightly.repo || handle_error "Adding Brave Nightly Repository"
else
  echo "Brave repository is already added."
fi

# --------- Group 1: Core desktop apps ---------
echo -e "\n--- Group 1: Core Desktop Apps (dolphin, kitty, flatpak, zed, Brave, Bazaar) ---"
read -p "Do you want to install ALL Group 1 apps? (y/N): " install_all_group1
if [[ "$install_all_group1" =~ ^[Yy]$ ]]; then
    echo "Installing all Group 1 apps..."
    dnf install -y dolphin kitty flatpak brave-origin-nightly || handle_error "Group 1 dnf packages"
    # Zed
    su - "$TARGET_USER" -c "command -v zed &>/dev/null || [ -f ~/.local/bin/zed ]" || {
        echo "Installing Zed editor..."
        su - "$TARGET_USER" -c "curl -f https://zed.dev/install.sh | sh" || echo "[FAIL] Zed installation"
    }
    # Bazaar
    if command -v flatpak &>/dev/null; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
        flatpak install -y flathub io.github.kolunmi.Bazaar || handle_error "Bazaar"
    else
        echo "[WARNING] Flatpak not installed, skipping Bazaar."
    fi
else
    echo "You can now choose which Group 1 apps to install."
    group1_packages=("dolphin" "kitty" "flatpak" "zed" "brave-origin-nightly" "bazaar")
    for PKG in "${group1_packages[@]}"; do
        case "$PKG" in
            zed)
                su - "$TARGET_USER" -c "command -v zed &>/dev/null || [ -f ~/.local/bin/zed ]" && echo "[SKIP] zed (already installed)" && continue
                read -p "Install Zed editor? [y/N]: " c
                if [[ "$c" =~ ^[Yy]$ ]]; then
                    su - "$TARGET_USER" -c "curl -f https://zed.dev/install.sh | sh" || echo "[FAIL] Zed installation"
                fi
                ;;
            bazaar)
                if ! command -v flatpak &>/dev/null; then
                    echo "[SKIP] Bazaar requires Flatpak which is not installed."
                    continue
                fi
                if flatpak list 2>/dev/null | grep -q io.github.kolunmi.Bazaar; then
                    echo "[SKIP] Bazaar (already installed)"
                    continue
                fi
                read -p "Install Bazaar (Flathub) GUI package manager? [y/N]: " c
                if [[ "$c" =~ ^[Yy]$ ]]; then
                    flatpak install -y flathub io.github.kolunmi.Bazaar || echo "[FAIL] Bazaar"
                fi
                ;;
            *)
                if is_installed_dnf "$PKG"; then
                    echo "[SKIP] $PKG (already installed)"
                    continue
                fi
                read -p "Install $PKG? [y/N]: " c
                [[ "$c" =~ ^[Yy]$ ]] && dnf install -y "$PKG" || echo "[FAIL] $PKG"
                ;;
        esac
    done
fi

# --------- Group 2: Gaming & utilities ---------
echo -e "\n--- Group 2: Gaming & Utility Apps (steam, mangohud, gamescope, etc.) ---"
group2_packages=("steam" "mangohud" "gamescope" "protontricks" "protonplus" "goverlay" "lact" "mpv" "loupe" "gnome-calculator" "qbittorrent" "kde-partitionmanager" "yazi" "fastfetch" "zsh" "rsync" "duf" "btop" "tldr" "htop" "distrobox" "podman")
read -p "Do you want to install ALL Group 2 apps? (y/N): " install_all_group2
if [[ "$install_all_group2" =~ ^[Yy]$ ]]; then
    echo "Installing all Group 2 apps..."
    dnf install -y --skip-broken "${group2_packages[@]}" || handle_error "Group 2 packages"
else
    echo "You can now choose which Group 2 apps to install."
    for PKG in "${group2_packages[@]}"; do
        if is_installed_dnf "$PKG"; then
            echo "[SKIP] $PKG (already installed)"
            continue
        fi
        read -p "Install $PKG? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] && dnf install -y "$PKG" || echo "[FAIL] $PKG"
    done
fi

# Firefox removal if Brave installed
if is_installed_dnf "brave-origin-nightly" || is_installed_dnf "brave-origin"; then
  if is_installed_dnf "firefox"; then
    read -p "Remove Firefox? [y/N]: " c
    if [[ "$c" =~ ^[Yy]$ ]]; then
        dnf remove -y firefox || echo "[WARNING] Could not remove Firefox"
    fi
  fi
fi

## Step 7 — Oh My Zsh (optional)
echo -e "\n---> Step 7: Oh My Zsh (optional)"
read -p "Install Oh My Zsh and set zsh as default shell? (y/N): " install_omz
if [[ "$install_omz" =~ ^[Yy]$ ]]; then
    # Ensure zsh is installed
    if ! is_installed_dnf "zsh"; then
        echo "zsh is not installed. Installing now..."
        dnf install -y zsh || handle_error "Installing zsh"
    fi

    echo "Installing Oh My Zsh (unattended) for user $TARGET_USER..."
    # Run the installer as the target user
    sudo -u "$TARGET_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
        || handle_error "Oh My Zsh installation"

    # Change the default shell to zsh for the target user (fully non-interactive)
    ZSH_PATH=$(which zsh)
    if [ "$ZSH_PATH" != "" ]; then
        echo "Changing default shell for $TARGET_USER to $ZSH_PATH..."
        usermod -s "$ZSH_PATH" "$TARGET_USER" || handle_error "Changing shell to zsh"
    else
        echo "[WARNING] zsh executable not found; shell not changed."
    fi
else
    echo "[SKIP] Oh My Zsh installation."
fi

## Step 8 — Snapper & Btrfs snapshot integration (optional)
echo -e "\n---> Step 8: Snapper & Btrfs snapshot integration"

# Track whether Snapper was installed for later reminder
INSTALL_SNAPPER=false

read -p "Set up Snapper & grub-btrfs for automatic snapshots on DNF transactions? (y/N): " install_snapper
if [[ ! "$install_snapper" =~ ^[Yy]$ ]]; then
    echo "[SKIP] Snapper integration not installed."
else
    INSTALL_SNAPPER=true
fi

if [ "$INSTALL_SNAPPER" = true ]; then
    # Check if root filesystem is Btrfs
    if ! findmnt -n -o FSTYPE / | grep -q btrfs; then
        echo "[WARNING] Root filesystem is not Btrfs – Snapper integration cannot be set up. Skipping."
        INSTALL_SNAPPER=false
    else
        echo "Installing Snapper and dependencies..."
        dnf install -y snapper libdnf5-plugin-actions btrfs-assistant inotify-tools make git python3 \
            || handle_error "Snapper packages"

        # Create Snapper configs if they don't exist
        [ -d /.snapshots ] || snapper -c root create-config / || handle_error "root snapper config"
        [ -d /home/.snapshots ] || snapper -c home create-config /home || handle_error "home snapper config"

        # Fix SELinux
        restorecon -RFv /.snapshots 2>/dev/null || true
        restorecon -RFv /home/.snapshots 2>/dev/null || true

        # Grant current user access
        snapper -c root set-config ALLOW_USERS="$TARGET_USER" SYNC_ACL=yes || handle_error "root ACL"
        snapper -c home set-config ALLOW_USERS="$TARGET_USER" SYNC_ACL=yes || handle_error "home ACL"
        # Disable timeline for /home (only use manual/DNF snapshots)
        snapper -c home set-config TIMELINE_CREATE=no || handle_error "home timeline off"

        # Exclude .snapshots from updatedb
        echo "Updating locate database configuration..."
        if grep -q '^PRUNENAMES' /etc/updatedb.conf; then
            grep -q '\.snapshots' /etc/updatedb.conf || \
                sed -i 's|^PRUNENAMES *= *"|PRUNENAMES = ".snapshots |' /etc/updatedb.conf
        else
            echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf
        fi

        # Install grub-btrfs
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

        # Rebuild GRUB menu to include snapshots
        echo "Regenerating GRUB configuration..."
        grub2-mkconfig -o /boot/grub2/grub.cfg || handle_error "grub2-mkconfig"

        # Create Snapper DNF5 action scripts
        echo "Installing DNF5 Snapper integration scripts..."

        cat > /usr/local/bin/snapper-desc.sh << 'DESCSCRIPT'
#!/bin/bash
# snapper-desc.sh - extract a snapshot description from the calling process
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
# snapper-gui-pkg.sh - capture GUI package actions for a nice description
PID="$1"
ACTION="$2"
NAME="$3"
STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PKG_FILE="$STATE_DIR/snapper_gui_${PID}"

desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
# Only proceed for GUI transactions
[[ "$desc" != "GUI" ]] && exit 0
# Only capture first package to avoid overwriting
[[ -f "$PKG_FILE" ]] && exit 0

case "$ACTION" in
    I|U|D|R) echo "GUI install ${NAME}" > "$PKG_FILE" ;;
    E|O)     echo "GUI remove ${NAME}" > "$PKG_FILE" ;;
esac
GUIPKGSCRIPT
        chmod 755 /usr/local/bin/snapper-gui-pkg.sh

        cat > /usr/local/bin/snapper-pre.sh << 'PRESCRIPT'
#!/bin/bash
# snapper-pre.sh - create pre snapshot and store metadata
PID="$1"
STATE_DIR="/run/snapper-actions"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# Ensure libdnf5 sysimage directory exists to avoid packages.toml error
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
# snapper-post.sh - create post snapshot and clean up
PID="$1"
STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PRE_FILE="$STATE_DIR/snapper_pre_${PID}"
GUI_FILE="$STATE_DIR/snapper_gui_${PID}"

desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
pre=$(cat "$PRE_FILE" 2>/dev/null || echo "")
gui_pkg=$(cat "$GUI_FILE" 2>/dev/null || echo "")

# Nothing to do if no pre snapshot exists
[[ -z "$pre" ]] && exit 0

# Improve description with GUI info
if [[ -n "$gui_pkg" ]]; then
    desc="$gui_pkg"
    snapper -c root modify -d "$desc" "$pre" || true
fi

# Best-effort WAL checkpoint (non-fatal)
/usr/local/bin/snapper-wal-checkpoint.sh || true

# Create post snapshot linked to pre
snapper -c root create -c number -t post --pre-number "$pre" -d "$desc"

# Clean up runtime files
rm -f "$DESC_FILE" "$PRE_FILE" "$GUI_FILE"
POSTSCRIPT
        chmod 755 /usr/local/bin/snapper-post.sh

        cat > /usr/local/bin/snapper-wal-checkpoint.sh << 'WALSCRIPT'
#!/bin/bash
# snapper-wal-checkpoint.sh - force SQLite WAL checkpoint for rpmdb
python3 - << 'EOF'
import sqlite3
import sys
import time

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
WALSCRIPT
        chmod 755 /usr/local/bin/snapper-wal-checkpoint.sh

        # Restore SELinux contexts on the new scripts
        restorecon -v /usr/local/bin/snapper-*.sh 2>/dev/null || true

        # Install DNF5 actions configuration
        mkdir -p /etc/dnf/libdnf5-plugins/actions.d
        cat > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions << 'ACTIONS'
# Snapper pre/post snapshots for DNF5
# PRE snapshot
pre_transaction::::/usr/local/bin/snapper-pre.sh ${pid}

# Capture GUI package info (incoming packages)
pre_transaction:*:in::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}

# Capture GUI package info (outgoing packages)
pre_transaction:*:out::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}

# POST snapshot (with WAL fix)
post_transaction::::/usr/local/bin/snapper-post.sh ${pid}
ACTIONS

        # Enable Snapper timers (timeline snapshots for root only)
        systemctl enable --now snapper-timeline.timer || handle_error "snapper-timeline.timer"
        systemctl enable --now snapper-cleanup.timer || handle_error "snapper-cleanup.timer"

        echo "Snapper integration completed."
    fi
fi

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
echo " 2. In KDE System Settings:"
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
