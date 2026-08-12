#!/bin/bash
# Fedora-post-install setup – modular

set -euo pipefail

# ──── ROOT CHECK ────
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Do not run this script as root!"
    echo "Run as your normal user account with sudo available."
    exit 1
fi

# ── Define Environment Variables ──────────────────────────────────────────
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# Validate user exists
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    echo "ERROR: Invalid user or home directory for $TARGET_USER" >&2
    exit 1
fi

# ── Parse command line arguments ──────────────────────────────────────────
SKIP_UPDATE=false
SKIP_DNF=false
SKIP_RPM=false
SKIP_DE=false
SKIP_VIRT=false
SKIP_DISTRO=false
SKIP_CACHY=false
SKIP_APPS=false
SKIP_SHADER=false
SKIP_SHELL=false
SKIP_WAIT=false
SKIP_CODEC=false

for arg in "$@"; do
    case "$arg" in
        --skip-update)   SKIP_UPDATE=true ;;
        --skip-dnf)   SKIP_DNF=true ;;
        --skip-rpm)   SKIP_RPM=true ;;
        --skip-de)    SKIP_DE=true ;;
        --skip-virt)  SKIP_VIRT=true ;;
        --skip-distro) SKIP_DISTRO=true ;;
        --skip-cachy) SKIP_CACHY=true ;;
        --skip-apps)  SKIP_APPS=true ;;
        --skip-shader) SKIP_SHADER=true ;;
        --skip-shell) SKIP_SHELL=true ;;
        --skip-wait)  SKIP_WAIT=true ;;
        --skip-codec) SKIP_CODEC=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# ── Helper functions ──────────────────────────────────────────────────────
is_installed_dnf() {
    rpm -q "$1" &>/dev/null
}

warn() {
    echo "[WARNING] $*" >&2
}

error_exit() {
    echo "[ERROR] $*" >&2
    exit 1
}

enable_copr_if_needed() {
    local copr_repo="$1"
    if ! sudo dnf copr list 2>/dev/null | grep -qF "$copr_repo"; then
        sudo dnf copr enable -y "$copr_repo" || warn "Failed to enable COPR: $copr_repo"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local answer

    while true; do
        read -r -p "$prompt [y/N]: " answer
        case "${answer:-$default}" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

echo "──────────────────────────────────────────"
echo " Fedora Post-Install Setup"
echo "──────────────────────────────────────────"

# =========================================================================
# STAGE 1 – Full System Update
# =========================================================================
echo -e "\n▶ Stage 1: System update - Recommended before installing new softwares"
if [ "$SKIP_UPDATE" = false ]; then
    if ask_yes_no "Perform full System update?"; then
        sudo dnf upgrade --refresh -y || warn "System update failed"
        sudo dnf install dnf-plugin-system-upgrade || warn "System update failed"
        if command -v flatpak &>/dev/null; then
            sudo flatpak update -y || warn "Flatpak update failed"
        fi
    else    
        echo "[SKIP] System update skipped"
    fi
fi
    
# =========================================================================
# STAGE 2 – RPM Fusion Repos
# =========================================================================
echo -e "\n▶ Stage 2: RPM Fusion Repos"
if [ "$SKIP_RPM" = false ]; then
    if ask_yes_no "Enable RPM Fusion (free & non‑free) repositories?"; then
        echo "Checking RPM Fusion repos..."
        if ! is_installed_dnf "rpmfusion-free-release" || ! is_installed_dnf "rpmfusion-nonfree-release"; then
            echo "Enabling RPM Fusion Free..."
            sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm || warn "RPM Repo installation failed"
            sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm  || warn "RPM Non free Repo installation failed"
        else
            echo "[SKIP] RPM Fusion Free and Non‑Free is already installed."
        fi
    else
        echo "[SKIP] RPM Fusion"
    fi
else
    echo "[SKIP] RPM Fusion (flag)"
fi

# =========================================================================
# STAGE 3 – Desktop Environment and shell
# =========================================================================
echo -e "\n▶ Stage 3: Desktop Environment Setup"
if [ "$SKIP_DE" = false ]; then
    if ask_yes_no "Set up Desktop Environment (Noctalia & kineticwe)?"; then
        echo "Checking Kineticwe and Noctalia..."
        if ! is_installed_dnf "kineticwe" || ! is_installed_dnf "noctalia-git"; then
            echo "Installing..."
            enable_copr_if_needed "lionheartp/Hyprland"
            enable_copr_if_needed "theblackdon/kineticwe"
            sudo dnf install -y --skip-unavailable kineticwe noctalia-git || warn "Desktop Environment and shell installation failed"
        else
            echo "[SKIP] Kineticwe and Noctalia are already installed."
        fi
    else
        echo "[SKIP] Desktop Environment setup"
    fi
else
    echo "[SKIP] Desktop Environment (--skip-de flag)"
fi

# =========================================================================
# STAGE 4 – Virtualization
# =========================================================================
if [ "$SKIP_VIRT" = false ]; then
    if ask_yes_no "Install virtualization environment?"; then
        if ! command -v virt-manager &> /dev/null; then
            echo "Installing virtualization environment..."
            sudo dnf install -y @virtualization || { echo "Virtualization environment installation failed"; exit 1; }

            for SOCK in virtqemud.socket virtnetworkd.socket virtstoraged.socket \
                        virtnodedevd.socket virtsecretd.socket \
                        virtnwfilterd.socket virtinterfaced.socket; do
              sudo systemctl enable --now "$SOCK"
            done
            sudo usermod -aG libvirt "$TARGET_USER"
            echo "Virtualization stack installed - Restart or logout for group membership to take effect."
        else
            echo "[SKIP] virt-manager is already installed."
        fi
    else
        echo "[SKIP] Virtualization"
    fi
else
    echo "[SKIP] Virtualization (--skip-virt flag)"
fi

echo -e "\n▶ Stage 4.5: Distrobox Setup"
if [ "$SKIP_DISTRO" = false ]; then
    if ask_yes_no "Install Distrobox stack?"; then
        if ! command -v distrobox >/dev/null 2>&1 || ! command -v podman >/dev/null 2>&1; then
            echo "Installing Podman and Distrobox..."
            sudo dnf install -y podman distrobox || warn "Distrobox installation failed"
        else
            echo "[SKIP] Podman and Distrobox already installed"
        fi
    else
        echo "[SKIP] Distrobox stack"
    fi
else
    echo "[SKIP] Distrobox (--skip-distro flag)"
fi

# =========================================================================
# STAGE 5 – Performance and Optimizations
# =========================================================================
echo -e "\n▶ Stage 5: Performance and Optimizations"

if [ "$SKIP_DNF" = false ]; then
    if ask_yes_no "Apply DNF optimisations?"; then
        echo "Applying DNF Optimisations..."
        sudo dnf config-manager setopt max_parallel_downloads=15 || warn "DNF optimisations failed"
        echo "DNF configuration updated."
    else
        echo "[SKIP] DNF optimisations"
    fi
else
    echo "[SKIP] DNF optimisations (flag)"
fi

if [ "$SKIP_WAIT" = false ]; then
    if ask_yes_no "Disable Network Manager Wait?"; then
        sudo systemctl disable NetworkManager-wait-online.service || warn "Failed to disable service"
        echo "Network Manager wait service disabled."
    else
        echo "[SKIP] Disable Network Manager Wait"
    fi
else
    echo "[SKIP] Disable Network Manager Wait (--skip-wait flag)"
fi

if [ "$SKIP_CACHY" = false ]; then
    echo "CachyOS Kernel with addons"

    if rpm -q kernel-cachyos &>/dev/null; then
        echo "[INFO] CachyOS Kernel is already installed. Skipping..."
    else
        if ask_yes_no "Install CachyOS Kernel and Performance Schedulers (this can take few minutes)?"; then
            enable_copr_if_needed "bieszczaders/kernel-cachyos"
            enable_copr_if_needed "bieszczaders/kernel-cachyos-addons"

            sudo dnf install -y --skip-unavailable \
                kernel-cachyos kernel-cachyos-devel-matched libdnf5-plugin-actions || warn "CachyOS kernel install failed"

            if rpm -q kernel-cachyos &>/dev/null; then
                if [ -d /boot/grub2 ]; then
                    sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d

                    sudo tee /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions > /dev/null << 'EOF'
# Set the latest CachyOS kernel as the default boot entry
post_transaction:kernel*:in::/usr/bin/sh -c "/usr/bin/grubby --set-default=/boot/$(ls /boot | grep vmlinuz.*cachy | sort -V | tail -1)"
EOF
                else
                    warn "GRUB not detected. You may need to manually select the CachyOS kernel in your boot menu."
                fi

                if dnf list --available cachyos-settings &>/dev/null; then
                    sudo dnf swap -y zram-generator-defaults cachyos-settings || warn "swapping cachyos-settings failed"
                    sudo dracut --regenerate-all -f || warn "dracut regeneration failed"
                    sudo dnf install -y scx-scheds-git scx-tools-git scx-manager || warn "cachyos schedule manager installation failed"
                else
                    warn "cachyos-settings package not available."
                fi
            else
                warn "CachyOS Kernel was not detected after installation."
            fi
        else
            echo "[SKIP] CachyOS Kernel setup"
        fi
    fi
else
    echo "[SKIP] CachyOS Kernel (--skip-cachy flag)"
fi

if [ "$SKIP_SHADER" = false ]; then
    if ask_yes_no "Increase shader cache size to 12GB (Can fix stutters on AMD GPUs)?"; then
        echo "Setting MESA_SHADER_CACHE_MAX_SIZE=12GB..."
        sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/environment.d"

        sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/environment.d/gaming.conf" > /dev/null << 'EOF'
# Increase shader cache size to 12GB
MESA_SHADER_CACHE_MAX_SIZE=12GB
EOF
        echo "Shader cache configuration written."
    else
        echo "[SKIP] Shader cache size"
    fi
else
    echo "[SKIP] Shader cache size (--skip-shader flag)"
fi

# =========================================================================
# STAGE 6 – Applications
# =========================================================================
echo -e "\n▶ Stage 6: Applications"
if [ "$SKIP_APPS" = false ]; then
    if ask_yes_no "Install Applications?"; then

        # --------- Group 1: Core Apps ---------
        echo -e "\n  Group 1: Core Apps"

        if ask_yes_no "  Install SDDM (Login manager)?"; then
            sudo dnf install -y --skip-unavailable sddm
            sudo systemctl set-default graphical.target
            sudo systemctl enable --force sddm.service || warn "Login manager install failed"
        fi

        if ask_yes_no "  Install Dolphin (file manager)?"; then
            sudo dnf install -y --skip-unavailable dolphin || warn "Dolphin install failed"
        fi

        if ask_yes_no "  Install Kitty (terminal)?"; then
            sudo dnf install -y --skip-unavailable kitty || warn "Kitty install failed"
        fi

        if ask_yes_no "  Install Brave origin (browser)?"; then
            sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo || warn "Brave repo install failed"
            if ! sudo dnf install -y --skip-unavailable brave-origin-nightly; || warn "Brave-origin install failed"   
            fi
        fi

        if ask_yes_no "  Install MPV (media player)?"; then
            sudo dnf install -y --skip-unavailable mpv || warn "MPV install failed"
        fi
        
        if ask_yes_no "  Install Timeshift (System Restore tool)?"; then
            sudo dnf install -y --skip-unavailable timeshift || warn "Timeshift install failed"
        fi
        
        if ask_yes_no "  Install Loupe (image viewer)?"; then
            sudo dnf install -y --skip-unavailable loupe || warn "Loupe install failed"
        fi

        if ask_yes_no "  Install Spectacle (Screen capture tool)?"; then
            sudo dnf install -y --skip-unavailable spectacle || warn "Spectacle install failed"
        fi

        FLATPAK_AVAILABLE=false
        if ask_yes_no "  Install Flatpak (and configure Flathub & Flatseal)?"; then
            sudo dnf install flatpak -y || warn "Flatpak install failed"
            sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || warn "Flathub install failed"
            sudo flatpak install -y flathub com.github.tchx84.Flatseal || warn "Flatseal install failed"
            FLATPAK_AVAILABLE=true
        else
            if command -v flatpak &>/dev/null; then
                FLATPAK_AVAILABLE=true
            else
                echo "  [SKIP] Flatpak setup"
            fi
        fi

        # --------- Group 2: Utility Apps ---------
        echo -e "\n  Group 2: Utility Apps"

        if ask_yes_no "  Install Calculator?"; then
            sudo dnf install -y --skip-unavailable gnome-calculator || warn "GNOME Calculator install failed"
        fi

        if ask_yes_no "  Install qBittorrent?"; then
            sudo dnf install -y --skip-unavailable qbittorrent || warn "qBittorrent install failed"
        fi

        if ask_yes_no "  Install KDE Partition Manager?"; then
            sudo dnf install -y --skip-unavailable kde-partitionmanager || warn "KDE Partition Manager install failed"
        fi

        if ask_yes_no "  Install Fastfetch (TUI tool for displaying system info)?"; then
            sudo dnf install -y --skip-unavailable fastfetch || warn "Fastfetch install failed"
        fi

        if ask_yes_no "  Install rsync (TUI tool for transferring and synchronizing files)?"; then
            sudo dnf install -y --skip-unavailable rsync || warn "rsync install failed"
        fi

        if ask_yes_no "  Install duf (TUI Disk Usage utility)?"; then
            sudo dnf install -y --skip-unavailable duf || warn "duf install failed"
        fi

        if ask_yes_no "  Install btop (TUI Resource Monitor)?"; then
            sudo dnf install -y --skip-unavailable btop || warn "btop install failed"
        fi

        if ask_yes_no "  Install htop (TUI process viewer)?"; then
            sudo dnf install -y --skip-unavailable htop || warn "htop install failed"
        fi
        
        if ask_yes_no "  Install pam-kwallet (Auto-unlock KDE Wallet on login)?"; then
            sudo dnf install -y --skip-unavailable pam-kwallet || warn "pam-kwallet install failed"
        fi

        # --------- Group 3: Gaming Apps ---------
        echo -e "\n  Group 3: Gaming Apps"

        if ask_yes_no "  Install Steam?"; then
            sudo dnf install -y --skip-unavailable steam || warn "Steam install failed"
        fi

        if ask_yes_no "  Install MangoHud (In game overlay for monitoring GPU/CPU usage,FPS)?"; then
            sudo dnf install -y --skip-unavailable mangohud || warn "MangoHud install failed"
        fi

        if ask_yes_no "  Install Gamescope (isolated compositor for HDR,FSR etc.)?"; then
            sudo dnf install -y --skip-unavailable gamescope || warn "Gamescope install failed"
        fi

        if ask_yes_no "  Install Protontricks (To install windows tools required for games, mods)?"; then
            sudo dnf install -y --skip-unavailable protontricks || warn "Protontricks install failed"
        fi

        if ask_yes_no "  Install Goverlay (GUI tool for mangohud)?"; then
            sudo dnf install -y --skip-unavailable goverlay || warn "GOverlay install failed"
        fi

        # --------- Group 4: Flatpak Apps ---------
        echo -e "\n  Group 4: Flatpak Apps"
        if [ "$FLATPAK_AVAILABLE" = false ]; then
            echo "  [SKIP] Flatpak apps skipped because Flatpak is not available."
        else
            if ask_yes_no "  Install Zed editor (text and code editor)?"; then
                sudo flatpak install -y flathub dev.zed.Zed || warn "Zed install failed"
            fi

            if ask_yes_no "  Install Bazaar (app store)?"; then
                sudo flatpak install -y flathub io.github.kolunmi.Bazaar || warn "Bazaar install failed"
            fi
            
            if ask_yes_no "  Install Pikabackup (For user files backup)?"; then
                sudo flatpak install -y flathub org.gnome.World.PikaBackup || warn "PikaBackup install failed"
            fi

            if ask_yes_no "  Install Kdenlive (Video Editor)?"; then
                sudo flatpak install -y flathub org.kde.kdenlive || warn "kdenlive install failed"
            fi

            if ask_yes_no "  Install Krita (Image Editor)?"; then
                sudo flatpak install -y flathub org.kde.krita || warn "Krita install failed"
            fi

            if ask_yes_no "  Install Audacity (Audio editor)?"; then
                sudo flatpak install -y flathub org.audacityteam.Audacity || warn "audacity install failed"
            fi

            if ask_yes_no "  Install DistroShelf (Distrobox gui)?"; then
                sudo flatpak install -y flathub com.ranfdev.DistroShelf || warn "DistroShelf install failed"
            fi

            if ask_yes_no "  Install ProtonPlus (To check and install proton versions)?"; then
                sudo flatpak install -y flathub com.vysp3r.ProtonPlus || warn "ProtonPlus install failed"
            fi

            if ask_yes_no "  Install ProtonUp-Qt (ProtonPlus alternative)?"; then
                sudo flatpak install -y flathub net.davidotek.pupgui2 || warn "ProtonUp-Qt install failed"
            fi
            
            if ask_yes_no "  Install Sunshine (Game streaming backend)?"; then
                sudo flatpak install -y flathub dev.lizardbyte.app.Sunshine || warn "Sunshine install failed"
            fi

            if ask_yes_no "  Install Moonlight (Game streaming client)?"; then
                sudo flatpak install -y flathub com.moonlight_stream.Moonlight || warn "Moonlight install failed"
            fi
        fi

        # --------- Group 5: Apps Requiring custom Repos ---------
        echo -e "\n  Group 5: Apps requiring custom repos"
        if ask_yes_no "  Install yazi (TUI file manager)?"; then
            if ! is_installed_dnf "yazi"; then
                if enable_copr_if_needed "lihaohong/yazi"; then
                    sudo dnf install -y yazi || warn "yazi install failed"
                fi
            else
                echo "  [SKIP] yazi (already installed)"
            fi
        fi

        if ask_yes_no "  Install faugus-launcher (Lightweight game launcher)?"; then
            if ! is_installed_dnf "faugus-launcher"; then
                if enable_copr_if_needed "faugus/faugus-launcher"; then
                    sudo dnf install -y faugus-launcher || warn "faugus-launcher install failed"
                fi
            else
                echo "  [SKIP] faugus-launcher (already installed)"
            fi
        fi

        if ask_yes_no "  Install Helium Browser (Lightweight firefox alternative)?"; then
            if ! is_installed_dnf "helium-bin"; then
                if enable_copr_if_needed "imput/helium"; then
                    sudo dnf install -y helium-bin || warn "Helium install failed"
                fi
            else
                echo "  [SKIP] Helium Browser (already installed)"
            fi
        fi
        
        if ask_yes_no "  Install lgl-system-loadout (Alternate GUI app for setting up Fedora)?"; then
            if ! is_installed_dnf "lgl-system-loadout"; then
                if enable_copr_if_needed "linuxgamerlife/lgl-system-loadout"; then
                    sudo dnf install -y --skip-unavailable lgl-system-loadout
                fi
            else
                echo "  [SKIP] lgl-system-loadout (already installed)"
            fi
        fi

        if ask_yes_no "  Install and set up LACT (GPU overclocking tool)?"; then
            if ! is_installed_dnf "lact"; then
                if enable_copr_if_needed "ilyaz/LACT"; then
                    sudo dnf install -y lact
                    sudo systemctl enable --now lactd || warn "lact install failed"
                fi
            else
                echo "  [SKIP] lact (already installed)"
            fi
        fi

    else
        echo "[SKIP] User Apps Installation"
    fi
else
    echo "[SKIP] User applications (--skip-apps flag)"
fi

# =========================================================================
# STAGE 7 – Video and Audio Codecs Setup
# =========================================================================
echo -e "\n▶ Stage 7: Video and Audio Codecs"
if [ "$SKIP_CODEC" = false ]; then
    if ask_yes_no "Install proprietary audio codecs?"; then
        sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y || warn "proprietary audio codecs swap failed"
    else
        echo "[SKIP] Proprietary audio codec Installation"
    fi

    if ask_yes_no "Install Mesa video drivers?"; then
        sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld || warn "Mesa swap failed"
        sudo dnf swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld || warn "Vulkan swap failed"
        
        if ask_yes_no "Install gstreamer video codecs?"; then
        sudo dnf install --setopt="install_weak_deps=False" -y \
            gstreamer1-plugins-good \
            gstreamer1-plugins-bad-free \
            gstreamer1-plugins-bad-freeworld \
            gstreamer1-plugins-ugly \
            gstreamer1-plugins-ugly-free \
            gstreamer1-plugin-openh264 \
            gstreamer1-plugin-libav \
            --exclude=PackageKit-gstreamer-plugin || warn "gstreamer plugin install failed"
            fi
        else
        echo "[SKIP] Proprietary video codecs Installation"
    fi
else
    echo "[SKIP] Video and audio codecs (--skip-codec flag)"
fi

# =========================================================================
# STAGE 8 – Terminal Setup (zsh, fish, starship)
# =========================================================================
echo -e "\n▶ Stage 8: Terminal Setup"
if [ "$SKIP_SHELL" = false ]; then
    SHELL_CHOICE="${SHELL_CHOICE:-skip}"

    if [ "$SHELL_CHOICE" = "skip" ]; then
        if ask_yes_no "Would you like to install and set up a custom shell (zsh or fish)?"; then
            while true; do
                read -r -p "Which shell? (zsh/fish): " shell_ans
                case "${shell_ans,,}" in
                    zsh) SHELL_CHOICE="zsh"; break ;;
                    fish) SHELL_CHOICE="fish"; break ;;
                    *) echo "Please answer 'zsh' or 'fish'." ;;
                esac
            done
        else
            SHELL_CHOICE="skip"
        fi
    fi

    # --- ZSH ---
    if [ "${SHELL_CHOICE,,}" = "zsh" ]; then
        echo "Setting up zsh..."
        if ! is_installed_dnf "zsh"; then
            sudo dnf install -y zsh || warn "zsh install failed"
        fi
        if command -v zsh &>/dev/null; then
            if ask_yes_no "Change default shell to zsh?"; then
                sudo chsh -s "/usr/bin/zsh" "$TARGET_USER" || warn "Could not change shell to zsh"
            else
                echo "[SKIP] Changing default shell to zsh"
            fi
        fi

    # --- FISH ---
    elif [ "${SHELL_CHOICE,,}" = "fish" ]; then
        echo "Setting up fish..."
        if ! is_installed_dnf "fish"; then
            sudo dnf install -y fish || warn "fish install failed"
        fi
        if command -v fish &>/dev/null; then
            if ask_yes_no "Change default shell to fish?"; then
                sudo chsh -s "/usr/bin/fish" "$TARGET_USER" || warn "Could not change shell to fish"
            else
                echo "[SKIP] Changing default shell to fish"
            fi
        fi
    else
        echo "[SKIP] Custom shell installation"
    fi

    # --- STARSHIP ---
    if ask_yes_no "Set up starship prompt?"; then
        if ! is_installed_dnf "starship"; then
            if enable_copr_if_needed "atim/starship"; then
                sudo dnf install -y starship || warn "starship install failed"
            fi
        fi

        if command -v starship &>/dev/null; then
            echo "Applying Starship preset (gruvbox-rainbow)..."
            sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config"
            sudo -u "$TARGET_USER" starship preset gruvbox-rainbow -o "$TARGET_HOME/.config/starship.toml" || \
                warn "Could not apply Starship preset"

            if [ "${SHELL_CHOICE,,}" = "fish" ]; then
                echo "Configuring Starship for fish..."
                fish_rc="$TARGET_HOME/.config/fish/config.fish"
                sudo -u "$TARGET_USER" mkdir -p "$(dirname "$fish_rc")"
                sudo -u "$TARGET_USER" touch "$fish_rc"

                if ! sudo -u "$TARGET_USER" grep -q "starship init" "$fish_rc" 2>/dev/null; then
                    echo -e "\n# Starship prompt setup" | sudo -u "$TARGET_USER" tee -a "$fish_rc" > /dev/null
                    echo "starship init fish | source" | sudo -u "$TARGET_USER" tee -a "$fish_rc" > /dev/null
                else
                    echo "[SKIP] Starship already configured in fish"
                fi
            elif [ "${SHELL_CHOICE,,}" = "zsh" ]; then
                echo "Configuring Starship for zsh..."
                shell_rc="$TARGET_HOME/.zshrc"
                sudo -u "$TARGET_USER" touch "$shell_rc"

                if ! sudo -u "$TARGET_USER" grep -q "starship init" "$shell_rc" 2>/dev/null; then
                    echo -e "\n# Starship prompt setup" | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                    echo 'eval "$(starship init zsh)"' | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                else
                    echo "[SKIP] Starship already configured in zsh"
                fi
            else
                # Starship installs to Bash if the user didn't explicitly choose Fish or Zsh
                echo "Configuring Starship for bash..."
                shell_rc="$TARGET_HOME/.bashrc"
                sudo -u "$TARGET_USER" touch "$shell_rc"

                if ! sudo -u "$TARGET_USER" grep -q "starship init" "$shell_rc" 2>/dev/null; then
                    echo -e "\n# Starship prompt setup" | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                    echo 'eval "$(starship init bash)"' | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                else
                    echo "[SKIP] Starship already configured in bash"
                fi
            fi
        fi
    else
        echo "[SKIP] Starship setup"
    fi
else
    echo "[SKIP] Shell setup (--skip-shell flag)"
fi

# =========================================================================
# Final Messages & DNF cleanup
# =========================================================================
echo -e "\n==================================================="
echo " INSTALLATION COMPLETE "
echo "==================================================="

echo -e "\n▶ Post-install DNF cleanup"
if ask_yes_no "Clean up leftover packages and DNF cache?"; then
    echo "Removing orphan packages..."
    sudo dnf autoremove -y || warn "dnf autoremove failed"
    sudo dnf clean all || warn "dnf clean failed"
else
    echo "[SKIP] DNF cleanup"
fi

echo ""
echo "MANUAL CONFIGURATIONS REQUIRED"
echo "---------------------------------------------------"
echo " 1. If starting the desktop from TTY, use cmd:"
echo "    - start-kineticwe"
echo " 2. For Noctalia admin prompt:"
echo "    - enable Polkit in Security settings."
echo " 3. Update grub:"
echo "    - sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
echo " 4. In KDE System Settings go to search section:"
echo "    - Disable File Search, Plasma Search, and KRunner History."
echo " 5. KDE Wallet Setup (for pam-kwallet auto-unlock):"
echo "    - When an app asks to create a wallet"
echo "    - Choose standard (Blowfish) encryption"
echo "    - And use your exact login password."
echo "==================================================="

echo -e "\nSystem changes require a reboot to take effect."
exit 0
