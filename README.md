# Introduction 
Enable or disable Overlay Filesystem or Write protect Boot partition via CLI. When deploying a raspberry, via script I wanted to be able to integrate this script into the deployment scripts and avoid corrupted SD-cards. This script uses the code from raspi-config but does not need user interaction for i.e. enabling the overlay fs and write protecting the boot partition. Run the script, reboot, done.

# Getting Started
1.	Needs root priviliges: use sudo
2.  Make executable: `chmod +x overlayFS.sh`
3.	run: `sudo ./overlayFS.sh  -o y -b y`

# Info
Used and altered the code from https://github.com/RPi-Distro/raspi-config/blob/master/raspi-config
