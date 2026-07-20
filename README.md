# fedora-post-install

My custom settings and repos with apps applied for fedora 44 headless install (automated script). 

Except for the Desktop Enviornment and shell and sddm everything is optional.

Disclaimers
- I am still learning so expect heavy use of AI.
- This project aggregates and compiles packages and repositories created by others. All credit and intellectual property rights (if any) belongs to their respective authors. 

Run using

	sudo dnf install git -y
	git clone https://github.com/Adriftgit/Fedora-post-install/
	cd Fedora-post-install
	chmod +x ./install.sh
	./install.sh

What it does

1. Optimises DNF performance
2. Enables base Repositories to install Kineticwe with Noctalia
3. Virtualization
5. Cachyos Kernel with addons
6. User Applications (listed below)


---
Optimizes DNF performance by adding
 
	max_parallel_downloads=10
	defaultyes=True

to sudo nano /etc/dnf/dnf.conf

Disables NetworkManager-wait-online.service
		
	sudo systemctl disable NetworkManager-wait-online.service
---
Enables and installs following custom repositories and base packages
- linuxgamerlife/lgl-system-loadout
- lionheartp/Hyprland with theblackdon/kineticwe 
- Configures display manager (SDDM) with
sudo systemctl set-default graphical.target 
sudo systemctl enable --force sddm.service

---
Virtualisation

  		sudo dnf install -y @virtualization
  		sudo systemctl enable libvirtd
  		sudo systemctl restart libvirtd
  
---
Installs custom performance kernel (CachyOS)
- bieszczaders/kernel-cachyos
- bieszczaders/kernel-cachyos-addons
- Sets latest CachyOS kernel as the default boot entry

---	
User Applications and repos if not added before
- wehagy/protonplus
- ilyaz/LACT
- lihaohong/yazi
- Installs steam mangohud gamescope protontricks protonplus goverlay lact mpv loupe gnome-calculator qbittorrent brave-origin-nightly dolphin kde-partitionmanager flatpak ZED editor yazi fastfetch zsh rsync duf btop tldr htop distrobox podman oh-my-zsh
- Installs Bazaar (from Bazzite) through flathub

---
Manual steps
- Polkit Security: Go to Noctalia settings > Search for security > Enable polkit agent.
- In KDE System Settings > Go to search:
- Disable File Search
- Disable Plasma Search
- Turn off History in KRunner
- Reboot system to apply changes
