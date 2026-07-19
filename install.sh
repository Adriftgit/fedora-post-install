#!/bin/bash
# ===================================================
# Custom Fedora Desktop Install Script (REVISED)
# kineticwe, noctalia, AMD, Btrfs, CachyOS, Gaming
# Includes full Snapper + grub‑btrfs integration
# ===================================================
set -e

# -------------------- Logging --------------------
LOG_FILE="/var/log/fedora-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Fedora Setup Started at $(date) ==="

# -------------------- Defaults --------------------
INSTALL_ALL_USER_PKGS=false
INSTALL_CACHYOS_KERNEL=false
ASK_CACHYOS=true
AUTO_REBOOT=false
INSTALL_SDDM=""
INSTALL_FIREWALLD=""
INSTALL_DNF_OPTIMIZE=""
INSTALL_GRAPHICS_DRIVERS=""
INSTALL_FFMPEG_LIBS=""
INSTALL_DNS_TWEAKS=""
INSTALL_LGL=false

# -------------------- Parse Arguments --------------------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user-pkgs) INSTALL_ALL_USER_PKGS=true ;;
        --cachyos) INSTALL_CACHYOS_KERNEL=true; ASK_CACHYOS=false ;;
        --no-cachyos) INSTALL_CACHYOS_KERNEL=false; ASK_CACHYOS=false ;;
        --sddm) INSTALL_SDDM=true ;;
        --no-sddm) INSTALL_SDDM=false ;;
        --ffmpeg-libs) INSTALL_FFMPEG_LIBS=true ;;
        --no-ffmpeg-libs) INSTALL_FFMPEG_LIBS=false ;;
        --dns-tweaks) INSTALL_DNS_TWEAKS=true ;;
        --no-dns-tweaks) INSTALL_DNS_TWEAKS=false ;;
        --all)
            INSTALL_ALL_USER_PKGS=true
            INSTALL_CACHYOS_KERNEL=true
            ASK_CACHYOS=false
            INSTALL_SDDM=true
            INSTALL_FIREWALLD=true
            INSTALL_DNF_OPTIMIZE=true
            INSTALL_GRAPHICS_DRIVERS=true
            INSTALL_FFMPEG_LIBS=true
            INSTALL_DNS_TWEAKS=true
            ;;
        --reboot) AUTO_REBOOT=true ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --user-pkgs       Automatically install optional user packages (Docker, KVM)"
            echo "  --cachyos         Automatically install CachyOS Kernel & Schedulers"
            echo "  --no-cachyos      Skip CachyOS Kernel installation"
            echo "  --sddm            Install SDDM display manager"
            echo "  --no-sddm         Skip SDDM installation (manual start with start-kineticwe)"
            echo "  --ffmpeg-libs     Install ffmpeg-libs, libva, libva-utils"
            echo "  --no-ffmpeg-libs  Skip ffmpeg-libs installation"
            echo "  --dns-tweaks      Set up DNS over TLS & disable NM wait-online"
            echo "  --no-dns-tweaks   Skip DNS tweaks"
            echo "  --all             Install all optional packages and features"
            echo "  --reboot          Automatically reboot at the end"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# -------------------- Internet Check --------------------
echo "Checking internet connectivity..."
if ! ping -c1 -W2 8.8.8.8 &>/dev/null; then
    echo "ERROR: No internet connection. Aborting."
    exit 1
fi
echo "Network is up."

# -------------------- Root Elevation --------------------
if [ "$EUID" -ne 0 ]; then
    echo "This script requires administrative privileges."
    echo "Requesting sudo access..."
    exec sudo bash "$0" "$@"
fi

TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# -------------------- Error Handling --------------------
handle_error() {
    local step="$1"
    echo -e "\n\e[31m[ERROR]\e[0m An error occurred during: $step"
    read -p "Do you want to ignore this and continue to the next step? (y/N): " choice
    case "$choice" in
        y|Y ) echo "Continuing script..."; return 0 ;;
        * ) echo "Aborting script."; exit 1 ;;
    esac
}

# -------------------- Helper Functions --------------------
is_installed_dnf() { rpm -q "$1" &>/dev/null; }

enable_copr() {
    # Enable COPR repository – skip if already enabled
    dnf copr enable -y "$1" 2>/dev/null || true
}

selinux_enabled() {
    command -v restorecon &>/dev/null && sestatus 2>/dev/null | grep -q "enabled"
}

# -------------------- Start --------------------
echo "==================================================="
echo "  Custom Fedora Desktop Install Script (REVISED)"
echo "  kineticwe, noctalia, AMD, CachyOS, Gaming"
echo "  Target User: $TARGET_USER ($TARGET_HOME)"
echo "  Log: $LOG_FILE"
echo "==================================================="

# -------------------- Step 1: DNF Optimisations & Network --------------------
echo -e "\n---> Step 1: DNF Optimisations & Network Tweaks"

# Install dnf-plugins-core early (needed for config-manager)
dnf install -y dnf-plugins-core || handle_error "Installing dnf-plugins-core"

# DNF optimisations (optional)
if [ -z "$INSTALL_DNF_OPTIMIZE" ]; then
    read -p "Apply DNF optimizations? (fastestmirror, parallel downloads, etc.) (Y/n): " choice_dnf
    [[ ! "$choice_dnf" =~ ^[Nn]$ ]] && INSTALL_DNF_OPTIMIZE=true || INSTALL_DNF_OPTIMIZE=false
fi

if [ "$INSTALL_DNF_OPTIMIZE" = true ]; then
    grep -q '^fastestmirror=True' /etc/dnf/dnf.conf || echo 'fastestmirror=True' >> /etc/dnf/dnf.conf
    grep -q '^max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
    grep -q '^defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' >> /etc/dnf/dnf.conf
    grep -q '^keepcache=True' /etc/dnf/dnf.conf || echo 'keepcache=True' >> /etc/dnf/dnf.conf
    echo "[OK] DNF optimizations applied."
else
    echo "[SKIP] DNF optimizations not applied."
fi

# DNS over TLS & disable NetworkManager-wait-online (optional)
if [ -z "$INSTALL_DNS_TWEAKS" ]; then
    read -p "Configure DNS over TLS (Cloudflare security) and disable NetworkManager-wait-online? (y/N): " choice_dns
    [[ "$choice_dns" =~ ^[Yy]$ ]] && INSTALL_DNS_TWEAKS=true || INSTALL_DNS_TWEAKS=false
fi

if [ "$INSTALL_DNS_TWEAKS" = true ]; then
    echo "Setting up DNS over TLS..."
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/99-dns-over-tls.conf << 'DNSCONF'
[Resolve]
DNS=1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 2606:4700:4700::1112#security.cloudflare-dns.com 2606:4700:4700::1002#security.cloudflare-dns.com
DNSOverTLS=yes
Domains=~.
DNSCONF
    systemctl restart systemd-resolved || handle_error "Restarting systemd-resolved"
    echo "Disabling NetworkManager-wait-online.service..."
    systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
    echo "[OK] DNS tweaks applied."
else
    echo "[SKIP] DNS tweaks not applied."
fi

# -------------------- Step 1b: Repositories --------------------
echo -e "\n---> Step 1b: Enabling Repositories"
enable_copr "theblackdon/kineticwe"
enable_copr "lionheartp/Hyprland"

read -p "Install lgl-system-loadout? (system monitoring overlay) (y/N): " choice_lgl
if [[ "$choice_lgl" =~ ^[Yy]$ ]]; then
    INSTALL_LGL=true
    enable_copr "linuxgamerlife/lgl-system-loadout"
fi

# RPM Fusion
dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    || handle_error "Installing RPM Fusion Repositories"

# Enable the repos (they are usually enabled by default, but ensure)
dnf config-manager --set-enabled rpmfusion-free rpmfusion-free-updates 2>/dev/null || true

# -------------------- Step 2: Desktop Environment & Core --------------------
echo -e "\n---> Step 2: Desktop Environment & Core Packages"

CORE_PACKAGES="dnf-plugins-core kineticwe noctalia"
[ "$INSTALL_LGL" = true ] && CORE_PACKAGES="$CORE_PACKAGES lgl-system-loadout"

dnf install -y $CORE_PACKAGES || handle_error "Installing Desktop Environment and Core Packages"

# SDDM (optional)
if [ -z "$INSTALL_SDDM" ]; then
    read -p "Install SDDM display manager? (Y/n): " choice_sddm
    [[ "$choice_sddm" =~ ^[Nn]$ ]] && INSTALL_SDDM=false || INSTALL_SDDM=true
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

# -------------------- Step 3: Hardware Drivers & Codecs --------------------
echo -e "\n---> Step 3: Hardware Drivers, Codecs & Media"

# ffmpeg-libs (optional)
if [ -z "$INSTALL_FFMPEG_LIBS" ]; then
    read -p "Install multimedia codecs (ffmpeg-libs, libva, libva-utils)? (Y/n): " choice_ffmpeg
    [[ "$choice_ffmpeg" =~ ^[Nn]$ ]] && INSTALL_FFMPEG_LIBS=false || INSTALL_FFMPEG_LIBS=true
fi

if [ "$INSTALL_FFMPEG_LIBS" = true ]; then
    dnf install -y ffmpeg-libs libva libva-utils || handle_error "Installing ffmpeg-libs and VA-API libs"
else
    echo "[SKIP] ffmpeg-libs not installed."
fi

# Graphics drivers (optional)
if [ -z "$INSTALL_GRAPHICS_DRIVERS" ]; then
    read -p "Install AMD graphics drivers and Vulkan support? (Y/n): " choice_gfx
    [[ "$choice_gfx" =~ ^[Nn]$ ]] && INSTALL_GRAPHICS_DRIVERS=false || INSTALL_GRAPHICS_DRIVERS=true
fi

if [ "$INSTALL_GRAPHICS_DRIVERS" = true ]; then
    echo "Installing graphics drivers..."

    # Swap/install VA-API freeworld driver
    if rpm -q mesa-va-drivers &>/dev/null; then
        dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || handle_error "Swapping mesa-va-drivers"
    else
        dnf install -y mesa-va-drivers-freeworld || handle_error "Installing mesa-va-drivers-freeworld"
    fi
    
    if rpm -q mesa-vulkan-drivers &>/dev/null; then
        dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || handle_error "Swapping mesa-vulkan-drivers"
    else
        dnf install -y mesa-vulkan-drivers-freeworld mesa-va-drivers-freeworld || handle_error "Installing mesa-vulkan-drivers-freeworld"
    fi

    dnf install -y mesa-dri-drivers vulkan-loader vulkan-tools libva-utils || handle_error "Graphics drivers"

    if ! grep -q "LIBVA_DRIVER_NAME=radeonsi" "$TARGET_HOME/.bashrc"; then
        echo "export LIBVA_DRIVER_NAME=radeonsi" >> "$TARGET_HOME/.bashrc"
        chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.bashrc"
    fi
    echo "[OK] Graphics drivers installed."
else
    echo "[SKIP] AMD graphics drivers and Vulkan support not installed."
fi

# -------------------- Step 4: Firewall & Virtualisation --------------------
echo -e "\n---> Step 4: Firewall and Virtualisation"

if [ -z "$INSTALL_FIREWALLD" ]; then
    read -p "Install Firewalld and GUI (firewall-config)? (Y/n): " choice_fw
    [[ "$choice_fw" =~ ^[Nn]$ ]] && INSTALL_FIREWALLD=false || INSTALL_FIREWALLD=true
fi

if [ "$INSTALL_FIREWALLD" = true ]; then
    dnf install -y firewalld firewall-config || handle_error "Installing Firewalld"
    systemctl enable --now firewalld || handle_error "Enabling Firewalld"
else
    echo "[SKIP] Firewalld not installed."
fi

# Docker
if [ "$INSTALL_ALL_USER_PKGS" = true ]; then
    install_docker="y"
else
    read -p "Install Docker Engine? (y/N): " install_docker
fi
if [[ "$install_docker" =~ ^[Yy]$ ]]; then
    curl -fsSL https://get.docker.com | sh || handle_error "Docker installer"
    systemctl enable --now docker || handle_error "Enabling Docker service"
    usermod -aG docker "$TARGET_USER" || handle_error "Adding user to docker group"
    echo "Docker installed."
fi

# KVM
if [ "$INSTALL_ALL_USER_PKGS" = true ]; then
    install_kvm="y"
else
    read -p "Install KVM/QEMU Virtualization? (y/N): " install_kvm
fi
if [[ "$install_kvm" =~ ^[Yy]$ ]]; then
    dnf install -y @virtualization libvirt || handle_error "Installing virtualization group"
    if [ -f /etc/libvirt/network.conf ]; then
        # Ensure firewall_backend is set
        grep -q '^firewall_backend =' /etc/libvirt/network.conf && \
            sed -i 's/^#*firewall_backend = .*/firewall_backend = "iptables"/' /etc/libvirt/network.conf || \
            echo 'firewall_backend = "iptables"' >> /etc/libvirt/network.conf
    fi
    systemctl enable --now libvirtd || handle_error "Enabling libvirtd"
    virsh net-autostart default || echo "[WARNING] Could not autostart default VM network"
fi

# -------------------- Step 5: CachyOS Kernel --------------------
echo -e "\n---> Step 5: CachyOS Kernel with addons"

if [ "$ASK_CACHYOS" = true ]; then
    read -p "Install CachyOS Kernel and Performance Schedulers? (y/N): " choice_cachy
    [[ "$choice_cachy" =~ ^[Yy]$ ]] && INSTALL_CACHYOS_KERNEL=true
fi

if [ "$INSTALL_CACHYOS_KERNEL" = true ]; then
    echo "Installing CachyOS Kernel & Tools..."
    enable_copr "bieszczaders/kernel-cachyos"
    enable_copr "bieszczaders/kernel-cachyos-addons"
    dnf install -y kernel-cachyos kernel-cachyos-devel-matched libdnf5-plugin-actions grubby \
        || handle_error "Installing CachyOS Kernel"

    mkdir -p /etc/dnf/libdnf5-plugins/actions.d
    cat << 'EOF' > /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions
# Set the latest CachyOS kernel as the default boot entry
post_transaction:kernel*:in::/usr/bin/sh -c "/usr/bin/grubby --set-default=/boot/\$(ls /boot | grep vmlinuz.*cachy | sort -V | tail -1)"
EOF

    # Swap zram if present
    if rpm -q zram-generator-defaults &>/dev/null; then
        dnf swap -y zram-generator-defaults cachyos-settings || handle_error "Swapping zram-generator-defaults"
    else
        dnf install -y cachyos-settings || handle_error "Installing cachyos-settings"
    fi

    dnf install -y scx-scheds-git scx-tools-git || handle_error "Installing CachyOS Schedulers"
    echo "[OK] CachyOS Kernel installed."
else
    echo "[INFO] Skipping CachyOS Kernel Installation."
fi

# -------------------- Step 6: User Applications --------------------
echo -e "\n---> Step 6: User Applications"

# Enable COPRs for apps
enable_copr "wehagy/protonplus"
enable_copr "ilyaz/LACT"
enable_copr "lihaohong/yazi"

# Brave repository
if [ ! -f /etc/yum.repos.d/brave-browser-nightly.repo ]; then
    echo "Adding Brave repository..."
    curl -fsSL https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo -o /etc/yum.repos.d/brave-browser-nightly.repo \
        || handle_error "Adding Brave Nightly Repository"
else
    echo "Brave repository is already added."
fi

# --------- Group 1: Core desktop apps ---------
echo -e "\n--- Group 1: Core Desktop Apps (dolphin, kitty, flatpak, zed, Brave, Bazaar) ---"
read -p "Do you want to install ALL Group 1 apps? (y/N): " install_all_group1
if [[ "$install_all_group1" =~ ^[Yy]$ ]]; then
    echo "Installing all Group 1 apps..."
    dnf install -y dolphin kitty flatpak brave-origin-nightly || handle_error "Group 1 dnf packages"
    # Install Flathub remote
    if command -v flatpak &>/dev/null; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
    # Zed
    su - "$TARGET_USER" -c "command -v zed &>/dev/null || [ -f ~/.local/bin/zed ]" || {
        echo "Installing Zed editor..."
        su - "$TARGET_USER" -c "curl -f https://zed.dev/install.sh | sh" || {
            echo "[INFO] Curl installation failed, attempting Flatpak backup..."
            if command -v flatpak &>/dev/null; then
                flatpak install -y flathub dev.zed.Zed || echo "[FAIL] Zed flatpak installation"
            else
                echo "[FAIL] Flatpak not available, Zed installation failed."
            fi
        }
    }
    # Bazaar
    if command -v flatpak &>/dev/null; then
        flatpak install -y flathub io.github.kolunmi.Bazaar || handle_error "Bazaar"
    else
        echo "[WARNING] Flatpak not installed, skipping Bazaar."
    fi
else
    # Interactive selection
    group1_packages=("dolphin" "kitty" "flatpak" "zed" "brave-origin-nightly" "bazaar")
    for PKG in "${group1_packages[@]}"; do
        case "$PKG" in
            zed)
                su - "$TARGET_USER" -c "command -v zed &>/dev/null || [ -f ~/.local/bin/zed ]" && echo "[SKIP] zed (already installed)" && continue
                read -p "Install Zed editor? [y/N]: " c
                if [[ "$c" =~ ^[Yy]$ ]]; then
                    su - "$TARGET_USER" -c "curl -f https://zed.dev/install.sh | sh" || {
                        echo "[INFO] Curl installation failed, attempting Flatpak backup..."
                        if command -v flatpak &>/dev/null; then
                            flatpak install -y flathub dev.zed.Zed || echo "[FAIL] Zed flatpak installation"
                        else
                            echo "[FAIL] Flatpak not available, Zed installation failed."
                        fi
                    }
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
    # Ensure Flathub remote is added if flatpak installed
    if command -v flatpak &>/dev/null; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
fi

# --------- Group 2: Gaming & utilities ---------
echo -e "\n--- Group 2: Gaming & Utility Apps (steam, mangohud, gamescope, etc.) ---"
group2_packages=("steam" "mangohud" "gamescope" "protontricks" "protonplus" "goverlay" "lact" "mpv" "loupe" "gnome-calculator" "qbittorrent" "kde-partitionmanager" "yazi" "fastfetch" "zsh" "rsync" "duf" "btop" "tldr" "htop" "distrobox" "podman")
read -p "Do you want to install ALL Group 2 apps? (y/N): " install_all_group2
if [[ "$install_all_group2" =~ ^[Yy]$ ]]; then
    echo "Installing all Group 2 apps..."
    dnf install -y --skip-broken "${group2_packages[@]}" || handle_error "Group 2 packages"
else
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

# -------------------- Step 7: Oh My Zsh --------------------
echo -e "\n---> Step 7: Oh My Zsh (optional)"
read -p "Install Oh My Zsh and set zsh as default shell? (y/N): " install_omz
if [[ "$install_omz" =~ ^[Yy]$ ]]; then
    if ! is_installed_dnf "zsh"; then
        echo "zsh is not installed. Installing now..."
        dnf install -y zsh || handle_error "Installing zsh"
    fi

    echo "Installing Oh My Zsh (unattended) for user $TARGET_USER..."
    sudo -u "$TARGET_USER" bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" -- --unattended \
        || handle_error "Oh My Zsh installation"

    ZSH_PATH=$(which zsh)
    if [ -n "$ZSH_PATH" ]; then
        echo "Changing default shell for $TARGET_USER to $ZSH_PATH..."
        usermod -s "$ZSH_PATH" "$TARGET_USER" || handle_error "Changing shell to zsh"
    else
        echo "[WARNING] zsh executable not found; shell not changed."
    fi
else
    echo "[SKIP] Oh My Zsh installation."
fi

# -------------------- Step 8: Snapper & Btrfs --------------------
echo -e "\n---> Step 8: Snapper & Btrfs snapshot integration"
INSTALL_SNAPPER=false

read -p "Set up Snapper & grub-btrfs for automatic snapshots on DNF transactions? (y/N): " install_snapper
if [[ "$install_snapper" =~ ^[Yy]$ ]]; then
    # Check root Btrfs
    if ! findmnt -n -o FSTYPE / | grep -q btrfs; then
        echo "[WARNING] Root filesystem is not Btrfs – Snapper integration cannot be set up. Skipping."
    else
        INSTALL_SNAPPER=true
        echo "Installing Snapper and dependencies..."
        dnf install -y snapper libdnf5-plugin-actions btrfs-assistant inotify-tools make git python3 \
            || handle_error "Snapper packages"

        # Create root config
        [ -d /.snapshots ] || snapper -c root create-config / || handle_error "root snapper config"

        # Home config only if /home is Btrfs
        if findmnt -n -o FSTYPE /home | grep -q btrfs; then
            [ -d /home/.snapshots ] || snapper -c home create-config /home || handle_error "home snapper config"
            # Set ACLs for home
            snapper -c home set-config ALLOW_USERS="$TARGET_USER" SYNC_ACL=yes || handle_error "home ACL"
            snapper -c home set-config TIMELINE_CREATE=no || handle_error "home timeline off"
        else
            echo "[WARNING] /home is not Btrfs – skipping home snapshots."
        fi

        # Fix SELinux
        if selinux_enabled; then
            restorecon -RFv /.snapshots 2>/dev/null || true
            [ -d /home/.snapshots ] && restorecon -RFv /home/.snapshots 2>/dev/null || true
        fi

        # Grant user access to root snapshots
        snapper -c root set-config ALLOW_USERS="$TARGET_USER" SYNC_ACL=yes || handle_error "root ACL"

        # Exclude .snapshots from updatedb
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

        # Rebuild GRUB
        echo "Regenerating GRUB configuration..."
        grub2-mkconfig -o /boot/grub2/grub.cfg || handle_error "grub2-mkconfig"

        # Clean up temp dir
        cd /
        rm -rf "$TMP_GRUB"

        # Create Snapper DNF5 action scripts
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
    if selinux_enabled; then restorecon -q /usr/lib/sysimage/libdnf5 2>/dev/null || true; fi
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

        # SELinux contexts for scripts
        if selinux_enabled; then
            restorecon -v /usr/local/bin/snapper-*.sh 2>/dev/null || true
        fi

        # Install DNF5 actions
        mkdir -p /etc/dnf/libdnf5-plugins/actions.d
        cat > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions << 'ACTIONS'
# Snapper pre/post snapshots for DNF5
pre_transaction::::/usr/local/bin/snapper-pre.sh ${pid}
pre_transaction:*:in::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}
pre_transaction:*:out::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}
post_transaction::::/usr/local/bin/snapper-post.sh ${pid}
ACTIONS

        # Enable Snapper timers
        systemctl enable --now snapper-timeline.timer || handle_error "snapper-timeline.timer"
        systemctl enable --now snapper-cleanup.timer || handle_error "snapper-cleanup.timer"

        echo "Snapper integration completed."
    fi
else
    echo "[SKIP] Snapper integration not installed."
fi

# -------------------- Final System Sync --------------------
# Now perform distro-sync to ensure everything is consistent
echo -e "\n---> Performing distro-sync to finalise system consistency..."
dnf distro-sync -y || handle_error "Distro Sync"

# -------------------- Final Messages --------------------
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

if findmnt -n -o FSTYPE / | grep -q btrfs && [ "$INSTALL_SNAPPER" = true ]; then
    echo ""
    echo " 3. Snapper & grub-btrfs integration is active."
    echo "    - Snapshots are created automatically on DNF transactions."
    echo "    - They appear in the GRUB boot menu under 'Advanced options'."
fi
if [ "$INSTALL_DNS_TWEAKS" = true ]; then
    echo ""
    echo " 4. DNS over TLS configured – check /etc/systemd/resolved.conf.d/99-dns-over-tls.conf"
fi
echo "==================================================="
echo "Log file: $LOG_FILE"
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
