#!/bin/bash

format_drive() {
	lsblk -f
	read -p 'Select Drive: ' drive
	[[ -z $drive ]] && return
	parted -s /dev/$drive mklabel gpt
	parted -s mkpart "EFI system partition" fat32 1MiB 1GiB set 1 esp on
	parted -s mkpart "root partition" ext4 1GiB 100% type 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
	mkfs.fat -F 32 /dev/$drive'p1'
	mkfs.ext4 /dev/$drive'p2'
}

mount_drive() {
	lsblk -f
	read -p 'Select Drive: ' drive
	[[ -z $drive ]] && break
	mount --mkdir /dev/$drive'p2' /mnt
	mount --mkdir /dev/$drive'p1' /mnt/boot
}

lscpu | grep -q AuthenticAMD && ucode=amd-ucode
lscpu | grep -q GenuineIntel && ucode=intel-ucode

configure_pacman() {
	sed -i 's/#Parallel/Parallel/' /etc/pacman.conf
	sed -i 's/#Color/Color/' /etc/pacman.conf
}

install_archlinux() {
	configure_pacman
	pacstrap -K /mnt base linux linux-firmware booster $ucode
	genfstab -U /mnt > /mnt/etc/fstab
}

chroot() {
	cp arch.sh /mnt
	arch-chroot /mnt
}

xorg_as_root() {
	mkdir -p /etc/X11
	echo 'needs_root_rights = yes' > /etc/X11/Xwrapper.config
}

limit_gpu_power() {
	echo '[Unit]
Description=Limit GPU Power

[Service]
ExecStart=/bin/nvidia-smi -pl 70

[Install]
WantedBy=graphical.target' > /etc/systemd/system/gpu-power-limit.service
	systemctl enable gpu-power-limit.service
}

enable_tcp_fastopen() {
	echo 'net.ipv4.tcp_fastopen = 3' > /etc/sysctl.d/10-network.conf
}

disable_coredump() {
	echo 'kernel.core_pattern=|/bin/false' > /etc/sysctl.d/50-coredump.conf
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
	echo '[Match]
Name=e*

[Network]
DHCP=yes' > /etc/systemd/network/20-wired.network
	systemctl enable systemd-networkd
}

generate_image() {
	pacman -Sy --needed --noconfirm linux $ucode booster
	/usr/lib/booster/regenerate_images
}

install_bootloader() {
	bootctl install
	echo 'default @saved
timeout menu-force
console-mode max' > /boot/loader/loader.conf
	echo "title   Arch Linux
linux   /vmlinuz-linux
initrd  /$ucode.img
initrd  /booster-linux.img
options root=UUID=$(findmnt / -o UUID -n) rw quiet" > /boot/loader/entries/arch.conf
}

configure_windows_dualboot() {
	pacman -Sy --needed --noconfirm edk2-shell
	cp /usr/share/edk2-shell/x64/Shell.efi /boot/shellx64.efi
	echo 'title   Windows
efi     /shellx64.efi
options -nointerrupt -nomap -noversion -exit -noconsoleout HD0b:EFI\Microsoft\Boot\Bootmgfw.efi' > /boot/loader/entries/windows.conf
}

configure() {
	limit_gpu_power
	enable_tcp_fastopen
	disable_coredump
	configure_pacman
	configure_locales
	configure_network
	generate_image
	install_bootloader
	configure_windows_dualboot
}

while true; do
	echo 'ARCH LINUX HELPER
-----------------
1. Format Drive
2. Mount Drive
3. Install ArchLinux
4. Chroot
5. Configure'
	read -p 'Select Option: ' option
	case $option in
		1) format_drive ;;
		3) mount_drive ;;
		4) install_archlinux ;;
		5) chroot ;;
		6) configure ;;
		*) exit ;;
	esac
	echo
done
