#!/bin/bash
# Fedora-post-install setup – modular

set -euo pipefail

# ── Define Environment Variables ──────────────────────────────────────────
# Grabs the user running the script (or the original user if run via sudo)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# ── Parse command line arguments ──────────────────────────────────────────
SKIP_DNF=false
SKIP_RPM=false
SKIP_DE=false
SKIP_SL=false
SKIP_SDDM=false
SKIP_VIRT=false
SKIP_DISTRO=false
SKIP_CACHY=false
SKIP_APPS=false
SKIP_SHADER=false
SKIP_SHELL=false
SKIP_UPDATE=false
SKIP_WAIT=false

for arg in "$@"; do
    case "$arg" in
        --skip-dnf)    SKIP_DNF=true ;;
        --skip-rpm)    SKIP_RPM=true ;;
        --skip-de)     SKIP_DE=true ;;
        --skip-sl)     SKIP_SL=true ;;
        --skip-sddm)   SKIP_SDDM=true ;;
        --skip-virt)   SKIP_VIRT=true ;;
        --skip-distro) SKIP_DISTRO=true ;;
        --skip-cachy)  SKIP_CACHY=true ;;
        --skip-apps)   SKIP_APPS=true ;;
        --skip-shader) SKIP_SHADER=true ;;
        --skip-shell)  SKIP_SHELL=true ;;
        --skip-update) SKIP_UPDATE=true ;;
        --skip-wait)   SKIP_WAIT=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ── Helper functions ──────────────────────────────────────────────────────
is_installed_dnf() {
    rpm -q "$1" &>/dev/null
}

warn() {
    echo "[WARNING] $*" >&2
}

enable_copr_if_needed() {
    local copr_repo="$1"
    if ! sudo dnf copr list 2>/dev/null | grep -qF "$copr_repo"; then
        sudo dnf copr enable -y "$copr_repo" || warn "Failed to enable COPR: $copr_repo"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-N}"   # Default: N
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
echo " Fedora Post-Install Setup - Modular"
echo "──────────────────────────────────────────"

# =========================================================================
# STAGE 1 – RPM Fusion Repos
# =========================================================================
echo "RPM Fusion Repos"
if [ "$SKIP_RPM" = false ]; then
    if ask_yes_no "Enable RPM Fusion (free & non‑free) repositories?"; then
        echo "Checking RPM Fusion repos..."
        if ! is_installed_dnf "rpmfusion-free-release" || ! is_installed_dnf "rpmfusion-nonfree-release"; then
            echo "Enabling RPM Fusion Free..."
            sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
            sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
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
# STAGE 2 – Desktop Environment and shell
# =========================================================================
echo "Desktop Environment and Shell setup"
if [ "$SKIP_DE" = false ]; then
    if ask_yes_no "Set up Desktop Environment (Noctalia & kineticwe)?"; then
        echo "Checking Kineticwe and Noctalia..."
        if ! is_installed_dnf "kineticwe" || ! is_installed_dnf "noctalia-git"; then
            echo "Installing.."
            enable_copr_if_needed "lionheartp/Hyprland"
            enable_copr_if_needed "theblackdon/kineticwe"
            sudo dnf install -y --skip-unavailable kineticwe noctalia-git
        else
            echo "[SKIP] Kineticwe and Noctalia are already installed."
        fi
    else
        echo "[SKIP] Desktop Environment setup"
    fi
else
    echo "[SKIP] Desktop Environment (flag)"
fi

# =========================================================================
# STAGE 3 – GUI setup wizard and login Manager
# =========================================================================
echo "Post install gui setup wizard (for additional packages not covered in this script)"
if [ "$SKIP_SL" = false ]; then
    if ask_yes_no "Set up lgl-system-loadout?"; then
        echo "Enabling Optional package for DE..."
        enable_copr_if_needed "linuxgamerlife/lgl-system-loadout"
        sudo dnf install -y --skip-unavailable lgl-system-loadout
    else
        echo "[SKIP] GUI setup wizard"
    fi
else
    echo "[SKIP] GUI setup wizard (flag)"
fi

echo "Setup Login Manager"
if [ "$SKIP_SDDM" = false ]; then
    if ask_yes_no "Set up SDDM?"; then
        echo "Enabling Display Manager for DE..."
        sudo dnf install -y --skip-unavailable sddm
        sudo systemctl set-default graphical.target
        sudo systemctl enable --force sddm.service
    else
        echo "[SKIP] Login Manager setup"
    fi
else
    echo "[SKIP] Login Manager (flag)"
fi

# =========================================================================
# STAGE 4 – Virtualization
# =========================================================================
echo "Setup Virtualization"
if [ "$SKIP_VIRT" = false ]; then
    if ask_yes_no "Install virtualization stack (virt-manager, libvirt)?"; then
        if ! command -v virt-manager &> /dev/null; then
            echo "virt-manager not found. Installing virtualization environment..."
            sudo dnf groupinstall -y @virtualization
            sudo systemctl enable libvirtd --now
            sudo usermod -aG libvirt "$TARGET_USER"
            echo "Virtualization stack installed - Restart or logout for group membership to take effect."
        else
            echo "virt-manager is already installed. Skipping installation."
        fi
    else
        echo "[SKIP] Virtualization"
    fi
else
    echo "[SKIP] Virtualization (flag)"
fi

echo "Distrobox Setup"
if [ "$SKIP_DISTRO" = false ]; then
    if ask_yes_no "Install Distrobox stack?"; then
        CONFIG_DIR="${TARGET_HOME}/.config/distrobox"
        INI_FILE="${CONFIG_DIR}/distrobox.ini"

        if ! command -v distrobox &> /dev/null || ! command -v podman &> /dev/null; then
            echo -e "Podman and Distrobox not found - Installing..."
            sudo dnf install -y podman distrobox
        else
            echo -e "Skipping Podman and Distrobox installation (already installed)"
        fi

        echo -e "[2/4] Configuring Rootless Podman mappings for ${TARGET_USER}..."
        if ! grep -q "^${TARGET_USER}:" /etc/subuid 2>/dev/null; then
            echo "Assigning subuids for ${TARGET_USER}..."
            sudo usermod --add-subuids 100000-165535 "${TARGET_USER}"
        fi

        if ! grep -q "^${TARGET_USER}:" /etc/subgid 2>/dev/null; then
            echo "Assigning subgids for ${TARGET_USER}..."
            sudo usermod --add-subgids 100000-165535 "${TARGET_USER}"
        fi

        sudo -u "$TARGET_USER" podman system migrate 2>/dev/null || true

        echo -e "[3/4] Creating declarative distrobox.ini manifest..."
        sudo -u "$TARGET_USER" mkdir -p "${CONFIG_DIR}"
        sudo -u "$TARGET_USER" tee "${INI_FILE}" > /dev/null << 'EOF'

# Arch Linux container (pre-configured with dev tools)
[arch]
image=ghcr.io/ublue-os/arch-toolbox:latest
additional_packages="git base-devel neofetch htop curl wget"
init=false
nvidia=false
pull=true
root=false
replace=false
start_now=false

# Ubuntu container
[ubuntu]
image=ghcr.io/ublue-os/ubuntu-toolbox:latest
additional_packages="git build-essential curl wget"
init=false
nvidia=false
pull=true
root=false
replace=false
start_now=false
EOF
        echo "Created manifest at: ${INI_FILE}"

        echo -e "[4/4] Adding shell aliases..."
        SHELL_HELPER='# Distrobox Bazzite-style convenience aliases
alias dbx="distrobox"
alias dbx-assemble="distrobox assemble create --file ~/.config/distrobox/distrobox.ini"
alias dbx-list="distrobox list"'

        for rc in "${TARGET_HOME}/.bashrc" "${TARGET_HOME}/.zshrc"; do
            if [ -f "$rc" ]; then
                if ! sudo -u "$TARGET_USER" grep -q "dbx-assemble" "$rc"; then
                    echo -e "\n${SHELL_HELPER}" | sudo -u "$TARGET_USER" tee -a "$rc" > /dev/null
                    echo "Added shell aliases to $rc"
                else
                    echo "Shell aliases already present in $rc"
                fi
            fi
        done
    else
        echo "[SKIP] Distrobox stack"
    fi
else
    echo "[SKIP] Distrobox (flag)"
fi

# =========================================================================
# STAGE 5 – Performance Optimasations (for kernel, shader size, DNF and network)
# =========================================================================
echo "Performance Optimisations"

if [ "$SKIP_DNF" = false ]; then
    if ask_yes_no "Apply DNF optimisations?"; then
        echo "Applying DNF Optimisations..."
        grep -q 'max_parallel_downloads' /etc/dnf/dnf.conf || {
            echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf > /dev/null
            echo 'defaultyes=True'           | sudo tee -a /etc/dnf/dnf.conf > /dev/null
        }
        echo "DNF configuration updated."
    else
        echo "[SKIP] DNF optimisations"
    fi
else
    echo "[SKIP] DNF optimisations (flag)"
fi

if [ "$SKIP_WAIT" = false ]; then
if ask_yes_no "Disable Network Manager Wait?"; then
        sudo systemctl disable NetworkManager-wait-online.service || warn "Failed to disable NetworkManager-wait-online.service"
        echo "NetworkManager-wait-online.service disabled."
    else
        echo "[SKIP] Disable Network Manager Wait"
    fi
else
    echo "[SKIP] Disable Network Manager Wait (flag)"
fi

if [ "$SKIP_CACHY" = false ]; then
    echo -e "\nCachyOS Kernel with addons"

    if rpm -q kernel-cachyos &>/dev/null; then
            echo "[INFO] CachyOS Kernel is already installed. Skipping..."
        else
            if ask_yes_no "Install CachyOS Kernel and Performance Schedulers?"; then
            enable_copr_if_needed "bieszczaders/kernel-cachyos"
            enable_copr_if_needed "bieszczaders/kernel-cachyos-addons"

            sudo dnf install -y --skip-unavailable \
                kernel-cachyos kernel-cachyos-devel-matched libdnf5-plugin-actions || warn "CachyOS kernel install failed"
        if rpm -q kernel-cachyos &>/dev/null; then
            sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d

            sudo tee /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions > /dev/null << 'EOF'
# Set the latest CachyOS kernel as the default boot entry
post_transaction:kernel*:in::/usr/bin/sh -c "/usr/bin/grubby --set-default=/boot/$(ls /boot | grep vmlinuz.*cachy | sort -V | tail -1)"
EOF

        if dnf list --available cachyos-settings &>/dev/null; then
                    sudo dnf swap -y zram-generator-defaults cachyos-settings || warn "swapping cachyos-settings failed"
                    sudo dracut -f || warn "dracut regeneration failed"
                    sudo dnf install -y scx-scheds-git scx-tools-git scx-manager || warn "cachyos schedule manager installation failed"
                else
                    echo "[WARNING] cachyos-settings package not available."
                fi
            else
                echo "[WARNING] CachyOS Kernel was not detected after installation."
            fi
        else
            echo "[SKIP] CachyOS Kernel setup"
        fi
    fi
else
    echo "[SKIP] CachyOS Kernel (flag)"
fi

if [ "$SKIP_SHADER" = false ]; then
    if ask_yes_no "Increase shader cache size to 12GB (for less stutters)?"; then
        echo "Setting MESA_SHADER_CACHE_MAX_SIZE=12GB..."
        sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/environment.d"
        sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/environment.d/gaming.conf" > /dev/null << 'EOF'
# Increase AMD's shader cache size to 12GB
MESA_SHADER_CACHE_MAX_SIZE=12GB
EOF
        echo "Shader cache configuration written."
    else
        echo "[SKIP] Shader cache size"
    fi
else
    echo "[SKIP] Shader cache size (flag)"
fi

# =========================================================================
# STAGE 6 – User Applications (core, utilities, gaming)
# =========================================================================
echo "User Applications"
if [ "$SKIP_APPS" = false ]; then
    if ask_yes_no "Install user applications (core, utilities, gaming)?"; then

        # --------- Group 1: Core Apps ---------
        echo -e "\nGroup 1: Core Apps (dolphin, kitty, flatpak, flathub, flatseal, zed, brave, bazaar)"
        if ask_yes_no "Install ALL Core Apps?"; then
            sudo dnf install -y dnf-plugins-core flatpak dolphin kitty || warn "Core system packages install failed"
            # Add brave
            sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo || warn "Brave origin install failed"
            sudo dnf install -y brave-origin-nightly || warn "Brave install failed"
            # set up Flatpak
            flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            flatpak update --user -y
            flatpak install --user -y flathub com.github.tchx84.Flatseal || warn "Flatseal install failed"
            flatpak install --user -y flathub dev.zed.Zed  || warn "Zed install failed"
            flatpak install --user -y flathub io.github.kolunmi.Bazaar || warn "Bazaar install failed"
        else
            echo "Core Apps Installation skipped"
        fi

        # --------- Group 2: Utility Apps ---------
        echo -e "\nGroup 2: Utility Apps (mpv, loupe, calculator, qbittorrent, partitionmanager, fastfetch, rsync, duf, btop, htop)"
        if ask_yes_no "Install ALL utility apps?"; then
            sudo dnf install -y --skip-unavailable mpv loupe gnome-calculator qbittorrent kde-partitionmanager fastfetch rsync duf btop htop || warn "Utility Apps Installation failed"
        else
            echo "Utility Apps Installation skipped"
        fi

        # --------- Group 3: Gaming Apps ---------
        echo -e "\nGroup 3: Gaming Apps (steam, mangohud, gamescope, protontricks, goverlay)"
        if ask_yes_no "Install ALL Gaming apps?"; then
            sudo dnf install -y steam mangohud gamescope protontricks goverlay || warn "Gaming Apps Installation failed"
        else
            echo "Gaming Apps Installation skipped"
        fi

        # --------- Group 4: Content Creation apps ---------
        echo -e "\nGroup 4: Content Creation apps"

        if ask_yes_no "Install kdenlive?"; then
            if ! is_installed_dnf "kdenlive"; then
                sudo dnf install -y kdenlive || warn "kdenlive install failed"
            else
                echo "[SKIP] kdenlive already installed"
            fi
        fi

        if ask_yes_no "Install audacity?"; then
            flatpak install --user -y flathub org.audacityteam.Audacity || warn "audacity install failed"
        fi

        if ask_yes_no "Install krita?"; then
            if ! is_installed_dnf "krita"; then
                sudo dnf install -y krita || warn "krita install failed"
            else
                echo "[SKIP] krita already installed"
            fi
        fi

        # --------- Group 5: Apps that require repo ---------
        echo -e "\nGroup 5: Apps that require repo"
        if ask_yes_no "Install and set up yazi?"; then
            if ! is_installed_dnf "yazi"; then
                sudo dnf copr enable -y lihaohong/yazi
                sudo dnf install -y yazi || warn "yazi install failed"
            else
                echo "[SKIP] yazi (already installed)"
            fi
        fi

        if ask_yes_no "Install and set up faugus-launcher?"; then
            if ! is_installed_dnf "faugus-launcher"; then
                sudo dnf copr enable -y faugus/faugus-launcher
                sudo dnf install -y faugus-launcher || warn "faugus-launcher install failed"
            else
                echo "[SKIP] faugus-launcher (already installed)"
            fi
        fi

        if ask_yes_no "Install and set up protonplus?"; then
            if ! is_installed_dnf "protonplus"; then
                sudo dnf copr enable -y wehagy/protonplus
                sudo dnf install -y protonplus || warn "protonplus install failed"
            else
                echo "[SKIP] protonplus (already installed)"
            fi
        fi

        if ask_yes_no "Install and set up LACT?"; then
            if ! is_installed_dnf "lact"; then
                sudo dnf copr enable -y ilyaz/LACT
                sudo dnf install -y lact || warn "lact install failed"
            else
                echo "[SKIP] lact (already installed)"
            fi
        fi

    else
        echo "Core, Utility, Gaming, and Multimedia Apps Installation skipped"
    fi
else
    echo "[SKIP] User applications (flag)"
fi

# =========================================================================
# STAGE 7 – Video and audio codecs setup
# =========================================================================
echo "Video and audio codecs"
if ask_yes_no "Install proprietary audio codecs?"; then
    sudo dnf swap ffmpeg-free ffmpeg --allowerasing || warn "proprietary audio codecs swap failed"
else
    echo "Proprietary audio codec Installation skipped"
fi

if ask_yes_no "Install proprietary video codecs?"; then
    sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing -y || warn "Mesa swap failed"
    sudo dnf swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing -y || warn "Vulkan swap failed"
    sudo dnf install libavcodec-freeworld -y || warn "proprietary libva swap failed"
    sudo dnf install --setopt="install_weak_deps=False" \
        gstreamer1-plugins-good \
        gstreamer1-plugins-bad-free \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly \
        gstreamer1-plugins-ugly-free \
        gstreamer1-plugin-openh264 \
        gstreamer1-plugin-libav \
        --exclude=PackageKit-gstreamer-plugin || warn "gstreamer plugin swap failed"
else
    echo "Proprietary video codecs Installation skipped"
fi

# =========================================================================
# STAGE 8 – TUI Shell setup (zsh, starship)
# =========================================================================
echo "TUI Shell setup"
if [ "$SKIP_SHELL" = false ]; then
    zsh_installed=false
    fish_installed=false

    # Ask which shell to install (e.g., --shell fish)
    if [ -z "${SHELL_CHOICE:-}" ]; then
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
            zsh_installed=true
            if ask_yes_no "Change default shell to zsh?"; then
                sudo chsh -s "$(command -v zsh)" "$TARGET_USER" || warn "Could not change shell to zsh"
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
            fish_installed=true
            if ask_yes_no "Change default shell to fish?"; then
                sudo chsh -s "$(command -v fish)" "$TARGET_USER" || warn "Could not change shell to fish"
            else
                echo "[SKIP] Changing default shell to fish"
            fi
        fi
    else
        echo "[SKIP] Custom shell installation"
    fi

    # --- STARSHIP ---
    if ask_yes_no "Set up starship?"; then
        if ! is_installed_dnf "starship"; then
            sudo dnf copr enable -y atim/starship
            sudo dnf install -y starship || warn "starship install failed"
        fi

        if command -v starship &>/dev/null; then
            echo "Applying Starship preset (gruvbox-rainbow)..."
            sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config"
            sudo -u "$TARGET_USER" starship preset gruvbox-rainbow -o "$TARGET_HOME/.config/starship.toml" || \
                warn "Could not apply Starship preset"

            # Configure starship based on the chosen/installed shell
            if [ "$fish_installed" = true ] || { [ "${SHELL_CHOICE,,}" = "fish" ] && command -v fish &>/dev/null; }; then
                if ask_yes_no "Configure Starship for fish shell?"; then
                    fish_rc="$TARGET_HOME/.config/fish/config.fish"
                    init_cmd_fish='starship init fish | source'
                    echo "Configuring Starship for fish..."
                    sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/fish"
                    sudo -u "$TARGET_USER" touch "$fish_rc"
                    if ! sudo -u "$TARGET_USER" grep -q "starship init" "$fish_rc"; then
                        echo -e "\n# Starship prompt setup" | sudo -u "$TARGET_USER" tee -a "$fish_rc" > /dev/null
                        echo "$init_cmd_fish" | sudo -u "$TARGET_USER" tee -a "$fish_rc" > /dev/null
                    fi
                fi
            elif [ "$zsh_installed" = true ] || { [ "${SHELL_CHOICE,,}" = "zsh" ] && command -v zsh &>/dev/null; }; then
                shell_rc="$TARGET_HOME/.zshrc"
                init_cmd='eval "$(starship init zsh)"'
                echo "Configuring Starship for zsh..."
                sudo -u "$TARGET_USER" touch "$shell_rc"
                if ! sudo -u "$TARGET_USER" grep -q "starship init" "$shell_rc"; then
                    echo -e "\n# Starship prompt setup" | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                    echo "$init_cmd" | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                fi
            else
                shell_rc="$TARGET_HOME/.bashrc"
                init_cmd='eval "$(starship init bash)"'
                echo "Custom shell skipped. Defaulting Starship config to bash..."
                sudo -u "$TARGET_USER" touch "$shell_rc"
                if ! sudo -u "$TARGET_USER" grep -q "starship init" "$shell_rc"; then
                    echo -e "\n# Starship prompt setup" | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                    echo "$init_cmd" | sudo -u "$TARGET_USER" tee -a "$shell_rc" > /dev/null
                fi
            fi
        fi
    else
        echo "[SKIP] Starship setup"
    fi
else
    echo "[SKIP] Shell setup (flag)"
fi

# =========================================================================
# STAGE 9 – Full system update
# =========================================================================
echo "System update"
if [ "$SKIP_UPDATE" = false ]; then
    if ask_yes_no "Perform full system update (dnf upgrade & distro‑sync)?"; then
        echo -e "\nFull system update..."
        sudo dnf upgrade --refresh -y || warn "System upgrade encountered errors"
        sudo dnf distro-sync -y || warn "Distro-sync encountered errors"
    else
        echo "[SKIP] System update"
    fi
else
    echo "[SKIP] System update (flag)"
fi

# ===================================================
# Final messages & reboot
# ===================================================
echo -e "\n==================================================="
echo " INSTALLATION COMPLETE "
echo "==================================================="
echo "MANUAL CONFIGURATIONS REQUIRED"
echo "---------------------------------------------------"
echo " 1. If starting the desktop from TTY, use cmd:"
echo "    - start-kineticwe"
echo " 2. For Noctalia admin prompt"
echo "    - enable Polkit in Security settings."
echo " 3. Update grub:"
echo "    - sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
echo " 4. In KDE System Settings go to search section:"
echo "    - Disable File Search, Plasma Search, and KRunner History."
echo "==================================================="

echo -e "\nSystem changes require a reboot to take effect."

if ask_yes_no "Would you like to reboot the system now?"; then
    echo "Rebooting system..."
    sudo reboot
else
    echo "Reboot cancelled. Please remember to manually run 'sudo reboot' later."
fi
