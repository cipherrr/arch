#!/bin/bash

username=ag
lscpu | grep -q AuthenticAMD && ucode=amd-ucode
lscpu | grep -q GenuineIntel && ucode=intel-ucode

select_drive() {
	lsblk -f

	while true; do
		echo
		read -p 'Select Drive (or type "q" to cancel): ' drive
		echo

		if [ "$drive" = "q" ]; then
			echo "Canceled drive selection."
			echo
			return 1
		fi

		if ! lsblk /dev/$drive &> /dev/null; then
			echo "Error: '$drive' is not a disk."
			continue
		fi

		if ! lsblk /dev/$drive | grep -q disk; then
			echo "Error: '$drive' is not a disk."
			continue
		fi

		umount -q /dev/$drive*
		echo "Selected drive: $drive"
		return 0
	done
}

configure_pacman() {
	sed -i 's/#Color/Color/' /etc/pacman.conf
}

superuser() {
	mkdir -p /etc/sudoers.d
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/01_$username
	echo "$username ALL=(ALL:ALL) NOPASSWD: /bin/sh" >> /etc/sudoers.d/01_$username
}

autologin() {
	mkdir -p /etc/systemd/system/getty@tty1.service.d
	echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
	echo "Type=simple" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
	echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
	echo "ExecStart=/bin/agetty --autologin $username %I $TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
 	systemctl enable getty@tty1.service
}

nvidia_sleep() {
	systemctl enable nvidia-suspend nvidia-resume nvidia-powerd nvidia-persistenced
}

optimize_nvidia() {
	echo "options nvidia NVreg_UsePageAttributeTable=1" > /etc/modprobe.d/nvidia.conf
}

tcp_fastopen() {
	mkdir -p /etc/sysctl.d
	echo "net.ipv4.tcp_fastopen = 3" > /etc/sysctl.d/10-network.conf
}

disable_audio_powersave() {
	echo "options snd_hda_intel power_save=0" > /etc/modprobe.d/disable_audio_powersave.conf
}

disable_coredump() {
	mkdir -p /etc/sysctl.d
	echo "kernel.core_pattern=|/bin/false" > /etc/sysctl.d/50-coredump.conf
}

limit_journal_size() {
	mkdir /etc/systemd/journald.conf.d
	echo "[Journal]" > /etc/systemd/journald.conf.d/00-journal-size.conf
	echo "SystemMaxUse=50M" >> /etc/systemd/journald.conf.d/00-journal-size.conf
}

fstrim() {
	systemctl enable fstrim.timer
}

zram() {
	mkdir -p /etc/udev/rules.d
	echo 'ACTION=="add", KERNEL=="zram0", ATTR{initstate}=="0", ATTR{comp_algorithm}="lz4", ATTR{disksize}="16G", RUN="/usr/bin/mkswap -U clear %N", TAG+="systemd"' > /etc/udev/rules.d/99-zram.rules

  	if grep -q "/dev/zram0" /etc/fstab; then
   		echo "#/dev/zram0 none swap defaults,discard,pri=100 0 0" >> /etc/fstab
     		return
	fi
	echo "/dev/zram0 none swap defaults,discard,pri=100 0 0" >> /etc/fstab
}

locales() {
	ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
	echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf
	systemctl enable systemd-timesyncd
}

network() {
	mkdir -p /etc/systemd/network
	echo "[Match]" > /etc/systemd/network/20-wired.network
	echo "Name=enp5s0" >> /etc/systemd/network/20-wired.network
	echo >> /etc/systemd/network/20-wired.network
	echo "[Network]" >> /etc/systemd/network/20-wired.network
	echo "DHCP=yes" >> /etc/systemd/network/20-wired.network
	systemctl enable systemd-networkd systemd-resolved
}

firewall() {
	pacman -Sy --needed --noconfirm ufw
	ufw enable
}

generate_images() {
	pacman -Sy --needed --noconfirm linux $ucode booster
	/usr/lib/booster/regenerate_images
}

bootloader() {
	bootctl install
	mkdir -p /boot/loader/entries
	echo "default @saved" > /boot/loader/loader.conf
	echo "timeout menu-force" >> /boot/loader/loader.conf
	echo "console-mode max" >> /boot/loader/loader.conf

	echo "title   Arch Linux" > /boot/loader/entries/arch.conf
	echo "linux   /vmlinuz-linux" >> /boot/loader/entries/arch.conf
	echo "initrd  /$ucode.img" >> /boot/loader/entries/arch.conf
	echo "initrd  /booster-linux.img" >> /boot/loader/entries/arch.conf
	echo "options root=UUID=$(findmnt / -o UUID -n) rw quiet zswap.enabled=0" >> /boot/loader/entries/arch.conf
}

windows_dualboot() {
	pacman -Sy --needed --noconfirm edk2-shell
	cp /usr/share/edk2-shell/x64/Shell.efi /boot/shellx64.efi
	mkdir -p /boot/loader/entries
	echo "title   Windows" > /boot/loader/entries/windows.conf
	echo "efi     /shellx64.efi" >> /boot/loader/entries/windows.conf
	echo "options -nointerrupt -nomap -noversion -exit -noconsoleout" >> /boot/loader/entries/windows.conf
	echo "HD0b:EFI\Microsoft\Boot\Bootmgfw.efi" >> /boot/loader/entries/windows.conf
}

while true; do
	echo "+-------------------+"
	echo "| ARCH LINUX HELPER |"
	echo "+-------------------+"
	echo "| 1 | Format Drive"
	echo "| 2 | Mount Drive"
	echo "| 3 | Install ArchLinux"
	echo "| 4 | Change Root"
	echo "| 5 | Configure"
	echo "| 6 | Exit"

	while true; do
		echo
		read -p "> " option
		echo
		[[ $option =~ ^[1-6]$ ]] && break
		echo "Error: Invalid option."
	done

	case $option in
		1)
	  		select_drive
			[ $? -eq 1 ] && return
			parted -s /dev/$drive mklabel gpt
			parted -s mkpart "EFI System Partition" fat32 1MiB 1GiB set 1 esp on
			parted -s mkpart "Root Partition" ext4 1GiB 100% type 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
			mkfs.fat -F 32 /dev/$drive"p1"
			mkfs.ext4 /dev/$drive"p2"
	    		;;
		2)
		  	select_drive
			[ $? -eq 1 ] && return
			mount --mkdir /dev/$drive"p2" /mnt
			mount --mkdir /dev/$drive"p1" /mnt/boot
		 	;;
		3)
		  	configure_pacman
			pacstrap -K /mnt base linux linux-firmware booster $ucode
			genfstab -U /mnt > /mnt/etc/fstab
		  	;;
		4)
			cp arch.sh /mnt
			arch-chroot /mnt
		 	;;
		5)
  			superuser
			autologin
			nvidia_sleep
   			optimize_nvidia
			tcp_fastopen
   			disable_audio_powersave
			disable_coredump
			fstrim
			zram
			configure_pacman
			locales
			network
			generate_images
			bootloader
			windows_dualboot
		 	;;
		6) exit;;
	esac
done
