
**Fedora Post-Install Script:**

- My custom, automated post-installation script for Fedora 44 headless install. Everything in this script is modular and optional, designed to setup fully configured desktop and gaming environment. 
- Recommended to install at least Desktop Environment and Desktop Shell. 

**Disclaimers:** 

- Learning Project - Expect heavy use of AI assistance in crafting and optimising this script.
	
- Graphics and CPU optimisations are for AMD GPU and CPU as I can not test Nvidia GPU or Intel CPU.   

- This script aggregates and compiles packages and repositories created by other developers. 

- All credit and intellectual property rights (if any) belongs entirely to their respective authors.

**Recommendations** : 

While all options are modular, recommended to install at least Desktop Environment and Shell.

Run using

	sudo dnf install -y git
	git clone https://github.com/Adriftgit/fedora-post-install
	cd fedora-post-install
	chmod +x install.sh
	./install.sh
	
---	
**Script Functions**

- **System Updates & Repositories** - Automates system upgrades and enables RPM Fusion (Free & Non-Free).

- **Login manager** - Configures system to start with SDDM Login manager

- **DNF Cleanup** - Clears leftover packages and DNF cache post install
	
- Desktop Shell & Environment - Installs Kineticwe with Noctalia and lgl-system-loadout

	- linuxgamerlife/lgl-system-loadout
	- lionheartp/Hyprland
	- theblackdon/kineticwe
		
- **Virtualization** - Installs VM-Curator and distrobox and grants user permissions to manage virtual machines.
	
- **Performance Kernel** - Enables Cachyos kernel repositories and Installs Kernel and addons to manage its schedulers
	
	- bieszczaders/kernel-cachyos
	- bieszczaders/kernel-cachyos-addons
	
- **System Tweaks & Optimisations**
- Optimizes DNF performance by increasing maximum parallel downloads to 15.
- Disables Network Manager wait time by turning off NetworkManager-wait-online.service.
- Increases shader cache size to 12.
	
- **User Applications**

	Core/Essential apps
	- App store manager > flatpak flathub flatseal 
	- App store > bazaar 
	- Browser > Brave-origin-nightly 
	- File manager > Dolphin or Nautilus
	- Zip file manager > Ark
	- Terminal > Kitty
	- DejaDup > User file backup/restore tool
	- Timeshift > System restore tool
	- Rustdesk > Remote desktop tool	
	- Spectacle > Screen capture tool

	Utility apps
	- Media player > mpv
	- Image viewer > loupe
	- Calculator > gnome-calculator 
	- File sharing > qbittorrent 
	- For auto mounting external drives > kde partitionmanager
	- Other apps > fastfetch rsync duf btop htop distroshelf
   	- Kwallet autologin > pam-kwallet

	Text editing apps
	- Basic writer/ script editor > Kate
	- Spreadsheet editor > libreoffice calc
	- Powerpoint > libreoffice-impress
	- PDF sign/reader/editor > libreoffice-draw
	- Word processor > libreoffice-writer
	
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
	- imput/helium
	
- **Audio and video codecs:** Swaps to proprietary versions as Fedora excludes it due to patent restrictions

	- For Audio: Swaps ffmpeg-free for full ffmpeg

	- For Video:
		- Swaps mesa-va-drivers and mesa-vulkan-drivers with their freeworld variants.
		- GStreamer plugins (good, bad-free, bad-freeworld, ugly, ugly-free, openh264, libav)

- **Terminal UI Customization**

	Choice to install zsh or fish shell 
	Choice to install starship gruvbox theme for selected shell

---
**Recommended manual configurations post reboot**

	Polkit Security:
	- Open Noctalia settings
	- Search for security
	- Enable the polkit agent

	KDE System Settings Tweaks (Disable search services running in background as not used by noctalia)
	- Go to search and disable File Search
	- Disable Plasma Search
	- Turn off History in KRunner

	KDE Wallet Setup (for pam-kwallet auto-unlock):"
	- When an app asks to create a wallet"
	- Choose standard (Blowfish) encryption"
	- And use your exact login password."
