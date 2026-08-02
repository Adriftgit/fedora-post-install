Fedora Post-Install Script

My custom, automated post-installation script for Fedora 44 headless install. Everything in this script is modular and optional, designed to setup fully configured desktop and gaming environment. 
Recommended to install at least Desktop Environment and Desktop Shell

Disclaimers 

	Learning Project: Expect heavy use of AI assistance in crafting and optimizing this script.

	Attribution: This project aggregates and compiles packages and repositories created by other developers. 
	All credit and intellectual property rights (if any) belongs entirely to their respective authors.

Recommendation
		
	While all options are modular, recommended to install at least Desktop Environment and Shell.

Run using

	sudo dnf install git -y
	git clone https://github.com/Adriftgit/Fedora-post-install/
	cd Fedora-post-install
	chmod +x ./install.sh
	./install.sh
	
---	

Enables Repositories for base system application

	RPM Fusion free 
	RPM Fusion non-free
	
Desktop Shell & Environment - Installs Kineticwe with Noctalia and lgl-system-loadout

	linuxgamerlife/lgl-system-loadout
	lionheartp/Hyprland
	theblackdon/kineticwe
	
Login manager

	Configures system to start with SDDM display manager
	
Virtualization

	Installs virtualization packages and grants user permissions to manage virtual machines.
	Installs distrobox and adds arch and ubuntu containers
	
Performance Kernel

	Enables Cachyos kernel repositories and Installs Kernel, 
	Makes it default boot entry 
	Installs addons to manage its schedulers
	- bieszczaders/kernel-cachyos
	- bieszczaders/kernel-cachyos-addons
	
System Tweaks & Optimizations

	Optimizes DNF performance by increasing parallel downloads to 10 in dnf.conf.
	Disables Network Manager wait time by turning off NetworkManager-wait-online.service.
	Increases shader cache size to 12.
	
User Applications

	Core/Essential apps
	- App store manager > flatpak flathub flatseal 
	- App store > bazaar 
	- Browser > Brave-origin-nightly 
	- File manager > Dolphin 
	- Terminal > Kitty

	Utility apps
	- Media player > loupe 
	- Calculator > gnome-calculator 
	- File sharing > qbittorrent 
	- For auto mounting external drives > kde partitionmanager
	- Other apps > fastfetch rsync duf btop htop distroshel
   	
	Gaming apps
	- Steam faugus-launcher mangohud gamescope protonplus protontricks goverlay lact

	Multimedia and graphics apps
	- kdenlive krita audacity

	Installs following apps by enabling repos
	- wehagy/protonplus
	- ilyaz/LACT
	- lihaohong/yazi
	- atim/starship
	- faugus/faugus-launcher
	
Audio and video codecs - Swaps to proprietary versions as Fedora excludes it due to patent restrictions

	Audio: Swaps ffmpeg-free for full ffmpeg

	Video & Graphics:
	- Swaps mesa-va-drivers and mesa-vulkan-drivers for -freeworld variants.
	- libavcodec-freeworldInstalls 
	- GStreamer plugins (good, bad-free, bad-freeworld, ugly, ugly-free, openh264, libav)

Terminal UI Customization

	Choice to install zsh or fish shell 
	Choice to install starship gruvbox theme for selected shell

---
Recommended manual configurations post reboot

	Polkit Security:
	- Open Noctalia settings
	- Search for security
	- Enable the polkit agent

	KDE System Settings Tweaks (Disable search services running in background as not used by noctalia shell)
	- Go to search and disable File Search
	- Disable Plasma Search
	- Turn off History in KRunner
