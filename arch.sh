#!/bin/bash

lscpu | grep -q AuthenticAMD && ucode=amd-ucode
lscpu | grep -q GenuineIntel && ucode=intel-ucode

select_drive() {
	lsblk -f
	
	while true; do
		echo
		read -p 'Select Drive (or type "q" to cancel): ' drive
		echo
		
		if [ "$drive" = "q" ]; then
			echo 'Canceled drive selection.'
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

format_drive() {
	select_drive
	[ $? -eq 1 ] && return 1
	parted -s /dev/$drive mklabel gpt
	parted -s mkpart "EFI system partition" fat32 1MiB 1GiB set 1 esp on
	parted -s mkpart "root partition" ext4 1GiB 100% type 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
	mkfs.fat -F 32 /dev/$drive'p1'
	mkfs.ext4 /dev/$drive'p2'
}

mount_drive() {
	select_drive
	[ $? -eq 1 ] && return 1
	mount --mkdir /dev/$drive'p2' /mnt
	mount --mkdir /dev/$drive'p1' /mnt/boot
}

configure_pacman() {
	sed -i 's/#Color/Color/' /etc/pacman.conf
}

install_archlinux() {
	configure_pacman
	pacstrap -K /mnt base linux linux-firmware booster $ucode
	genfstab -U /mnt > /mnt/etc/fstab
}

change_root() {
	cp arch.sh /mnt
	arch-chroot /mnt
}

limit_gpu_power() {
	echo '[Unit]' > /etc/systemd/system/gpu-power-limit.service
	echo 'Description=Limit GPU Power' >> /etc/systemd/system/gpu-power-limit.service
	echo '' >> /etc/systemd/system/gpu-power-limit.service
	echo '[Service]' >> /etc/systemd/system/gpu-power-limit.service
	echo 'ExecStart=/bin/nvidia-smi -pl 80' >> /etc/systemd/system/gpu-power-limit.service
	echo '' >> /etc/systemd/system/gpu-power-limit.service
	echo '[Install]' >> /etc/systemd/system/gpu-power-limit.service
	echo 'WantedBy=graphical.target' >> /etc/systemd/system/gpu-power-limit.service
	systemctl enable gpu-power-limit.service
}

enable_nvidia_sleep() {
	systemctl enable nvidia-powerd nvidia-persistenced nvidia-suspend nvidia-resume nvidia-suspend-then-hibernate nvidia-hibernate
}

enable_tcp_fastopen() {
	echo 'net.ipv4.tcp_fastopen = 3' > /etc/sysctl.d/10-network.conf
}

disable_coredump() {
	echo 'kernel.core_pattern=|/bin/false' > /etc/sysctl.d/50-coredump.conf
}

set_swappiness() {
	echo 'vm.swappiness = 35' > /etc/sysctl.d/99-swappiness.conf
}

configure_locales() {
	ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
	echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
	locale-gen
	echo 'LANG=en_US.UTF-8' > /etc/locale.conf
	systemctl enable systemd-timesyncd
}

configure_network() {
	mkdir -p /etc/systemd/network
	echo '[Match]' > /etc/systemd/network/20-wired.network
	echo 'Name=e*' >> /etc/systemd/network/20-wired.network
	echo '' >> /etc/systemd/network/20-wired.network
	echo '[Network]' >> /etc/systemd/network/20-wired.network
	echo 'DHCP=yes' >> /etc/systemd/network/20-wired.network
	systemctl enable systemd-networkd
}

generate_image() {
	pacman -Sy --needed --noconfirm linux $ucode booster
	/usr/lib/booster/regenerate_images
}

install_bootloader() {
	bootctl install
	echo 'default @saved' > /boot/loader/loader.conf
	echo 'timeout menu-force' >> /boot/loader/loader.conf
	echo 'console-mode max' >> /boot/loader/loader.conf
	
	echo 'title   Arch Linux' > /boot/loader/entries/arch.conf
	echo 'linux   /vmlinuz-linux' >> /boot/loader/entries/arch.conf
	echo "initrd  /$ucode.img" >> /boot/loader/entries/arch.conf
	echo 'initrd  /booster-linux.img' >> /boot/loader/entries/arch.conf
	echo "options root=UUID=$(findmnt / -o UUID -n) rw quiet zswap.enabled=1" >> /boot/loader/entries/arch.conf
}

configure_windows_dualboot() {
	pacman -Sy --needed --noconfirm edk2-shell
	cp /usr/share/edk2-shell/x64/Shell.efi /boot/shellx64.efi
	echo 'title   Windows' > /boot/loader/entries/windows.conf
	echo 'efi     /shellx64.efi' >> /boot/loader/entries/windows.conf
	echo 'options -nointerrupt -nomap -noversion -exit -noconsoleout' >> /boot/loader/entries/windows.conf
	echo 'HD0b:EFI\Microsoft\Boot\Bootmgfw.efi' >> /boot/loader/entries/windows.conf
}

configure() {
	limit_gpu_power
	enable_nvidia_sleep
	enable_tcp_fastopen
	disable_coredump
	set_swappiness
	configure_pacman
	configure_locales
	configure_network
	generate_image
	install_bootloader
	configure_windows_dualboot
}

while true; do
	echo '+-------------------+'
	echo '| ARCH LINUX HELPER |'
	echo '+-------------------+'
	echo '1. Format Drive'
	echo '2. Mount Drive'
	echo '3. Install ArchLinux'
	echo '4. Change Root'
	echo '5. Configure'
	echo '6. Exit'
	
	while true; do
		echo
    	read -p 'Select an option: ' option
    	echo
    	[[ $option =~ ^[1-6]$ ]] && break
    	echo 'Error: Invalid option.'
  	done
    
	case $option in
		1) format_drive;;
		2) mount_drive;;
		3) install_archlinux;;
		4) change_root;;
		5) configure;;
		6) exit;;
	esac
done
