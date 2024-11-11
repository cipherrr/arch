#!/bin/bash

while true; do
	echo '---------------------'
	echo '| ARCH LINUX HELPER |'
	echo '---------------------'
	echo '1. Partition Disk'
	echo '2. Format Partition'
	echo '3. Mount Partition'
	echo '4. Install Essential Packages'
	echo '5. Generate fstab'
	echo '6. Chroot'
	read -p 'Select Option: ' option
	echo

	case $option in
		1)
			lsblk -f
			read -p 'Select Disk: ' disk
			echo
			cfdisk /dev/$disk
			echo
			;;
			
		2)
			lsblk -f
			read -p 'Select Partition: ' part
			echo

			echo '1. fat32'
			echo '2. ext4'
			read -p 'Select File System: ' fs
			echo

			case $fs in
				1)	mkfs.fat -F 32 /dev/$part ;;
				2)	mkfs.ext4 /dev/$part ;;
				*)	;;
			esac
			echo
			;;

		3)
			lsblk -f
			read -p 'Select Partition: ' part
			echo
			
			echo '1. /'
			echo '2. /boot'
			echo '3. /efi'
			echo '4. /home'
			read -p 'Select Mount Point: ' mp
			echo
			
			case $mp in
				1)	mount --mkdir /dev/$part /mnt ;;
				2)	mount --mkdir /dev/$part /mnt/boot ;;
				3)	mount --mkdir /dev/$part /mnt/efi ;;
				4)	mount --mkdir /dev/$part /mnt/home ;;
				*)	;;
			esac
			echo
			;;
		
		4)
			pacstrap -K /mnt base linux linux-firmware
			echo
			;;
		
		5)
			genfstab -U /mnt >> /mnt/etc/fstab
			echo
			;;
		
		6)
			arch-chroot /mnt
			echo
			;;
			
		*)	;;
	esac
done