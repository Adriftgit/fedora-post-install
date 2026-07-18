# fedora-post-install

My custom settings and repos with apps applied for fedora 44 headless install (automated script). 

Except for the Desktop Enviornment and shell everything is optional.

Disclaimer: I am still learning so expect heavy use of ai.

Run using

	sudo dnf install git -y
	git clone https://github.com/Adriftgit/Fedora-post-install/
	cd Fedora-post-install
	chmod +x ./install.sh
	./install.sh

What it does

1. Optimises DNF performance
2. Enables base Repositories with Choice to install Kineticwe with Noctalia and/or Hyprland
3. Installs Mesa, Vulkan Drivers and ffmpg Codecs
4. Firewall and Virtualization
5. Cachyos Kernel with sch-ext addons
6. User Applications (listed below)
7. Btrfs Snapshots, Compression & System Recovery Setup

---
Optimizes DNF performance by adding
 
	fastestmirror=True
	max_parallel_downloads=10
	defaultyes=True
	keepcache=True

to sudo nano /etc/dnf/dnf.conf

---
Enables and installs following custom repositories and base packages
- linuxgamerlife/lgl-system-loadout (optional)
- dnf-plugins-core
- lionheartp/Hyprland with theblackdon/kineticwe 
- Hyprland (optional)
- Can be used to manually add dank material shell and add it to only run with hyprland
  - Add following to ~/.config/hypr/hyprland.lua to achieve this
  
		hl.on("hyprland.start", function()
		hl.exec_cmd("dms run")
		end)
			
- RPM Fusion both free and non-free branches
- Configures display manager (SDDM) with
sudo systemctl set-default graphical.target 
sudo systemctl enable --force sddm.service

---
Installs Mesa, Vulkan Drivers and ffmpg Codecs
- Swap Fedora's stripped-down codecs for full ffmpeg
- Installs Graphics stack Mesa, OpenGL, Vulkan drivers
- Installs AMD (radeonsi) libva-utils

---
Firewall, Docker, Virtualisation
- Firewall with

		sudo dnf install -y firewalld firewall-config
  		sudo systemctl enable --now firewalld
- Docker with

  		curl -fsSL https://get.docker.com | sh |
  		systemctl enable --now docker
- Virt-manager with

  		sudo dnf install -y @virtualization
  		sudo systemctl enable libvirtd
  		sudo systemctl restart libvirtd
  
---
Installs custom performance kernel (CachyOS)
- bieszczaders/kernel-cachyos
- bieszczaders/kernel-cachyos-addons
- Sets latest CachyOS kernel as the default boot entry
- Installs scx-manager scx-scheduler and scx-tools -git

---	
User Applications and repos if not added before
- wehagy/protonplus
- ilyaz/LACT
- lihaohong/yazi
- Installs steam mangohud gamescope protontricks protonplus goverlay lact mpv loupe gnome-calculator qbittorrent brave-origin-nightly dolphin plasma-discover kde-partitionmanager ZED editor yazi fastfetch zsh rsync duf btop tldr htop distrobox podman

---
Btrfs Snapshots, Compression & System Recovery Setup from
- https://github.com/SysGuides/sysguides-snapper-fedora
- Adds entry to grub to enable Btrfs compression
- Enables Btrfs dnf transaction snapshots
- Enables snapshot boot from grub

---
Manual steps
- Polkit Security: Go to Noctalia settings > Search for security > Enable polkit agent.
- In KDE System Settings > Go to search:
- Disable File Search
- Disable Plasma Search
- Turn off History in KRunner
- Reboot system to apply changes
