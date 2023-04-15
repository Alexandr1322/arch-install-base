#!/usr/bin/env bash

setfont cyr-sun16
# Ваш диск по умолчанию, на который будем ставить
DISK_DEFAULT="nvme0n1"
# Имена раделов
PARTED_EFI="p1"
PARTED_SYS="p2"
EFI_DIR="/mnt/system/efi"
SYS_DIR="/mnt/system"
#Форматирование текста
sp=$(sleep 0)
RED="\e[31m"
ORANGE="\e[33m"
BLUE="\e[94m"
L_BLUE="\e[96m"
YELLOW="\e[93m"
GREEN="\e[92m"
STOP="\e[0m"
bold=$(tput bold)
clear_l=$(tput ed)

# Базовые пакеты
p_base="base base-devel linux-lts linux-firmware amd-ucode intel-ucode xorg networkmanager"
## Драйвера
p_drv="r8168 nvidia nvidia-utils lib32-nvidia-utils"
## Шрифты
p_font="ttf-dejavu ttf-liberation ttf-font-awesome ttf-hack ttf-iosevka-nerd"

create_dir() {
	if [[ ! -d "$SYS_DIR" ]]; then
		mkdir -p $SYS_DIR
		mkdir -p $EFI_DIR
	else
		echo -e "$ORANGE Рабочая директория уже существует!"
	fi
}

fast_install() {
	clear
	echo -e $RED"<< ВНИМАНИЕ! >>"
	echo -e $ORANGE"Система будет установлена с настройками из готовой конфигурации:"
	echo -e $ORANGE" - Диск будет размечен автоматически\n"
	echo -e $ORANGE"Диск <DISK_DEFAULT> определяется по NAME <sda,sdb и.т.д>"
	echo -e $ORANGE"========================================"
	lsblk -o "NAME,MODEL,SIZE"
	echo -e $ORANGE"========================================"
	echo -e $BLUE;
	echo "Напишите имя диска из списка, на который будет установлена система"
	echo -e "Выйти в главное меню - 0"
	read -p '>> ' DISK_DEFAULT

	if [[ $DISK_DEFAULT = "0" ]]; then fast_install; fi

	clear;
	
	echo -e "<< Проверьте данные >>\n"
	
	echo -e $RED"Будьте внимательны, диск будет отформатирован и размечен в GPT\n"
	echo -e $GREEN" Диск: <${DISK_DEFAULT}> $(lsblk /dev/${DISK_DEFAULT} -o "MODEL,SIZE" -n)"
	echo -e $ORANGE
	echo "Все верно? [Y/n]"
	read -p '>> ' check_finstall
	
	if [[ "$check_finstall" = "1" ]]; then test; fi
	
	if [[ "$check_finstall" = "y" && "д" ]]; then fast_install2; fi

	if [[ "$check_finstall" = "n" && "н" ]]; then exit; else exit; fi

}

fast_install2() {
	echo -e $YELLOW"Размечаем.."
# Автоматическая разметка
	parted -s /dev/${DISK_DEFAULT} mklabel gpt
	parted -s /dev/${DISK_DEFAULT} mkpart fat32 0% 1024M
	parted -s /dev/${DISK_DEFAULT} set 1 esp on  
	parted -s /dev/${DISK_DEFAULT} mkpart primary 1024M 90%
	sleep 1
# Форматирование разделов
	mkfs.fat -F32 /dev/${DISK_DEFAULT}${PARTED_EFI}
	mkfs.ext4 /dev/${DISK_DEFAULT}${PARTED_SYS}
	cfdisk /dev/${DISK_DEFAULT}
	echo -e $YELLOW"Монтирование.."
# Монтирование разделов в папки
	create_dir
	mount -t auto /dev/${DISK_DEFAULT}${PARTED_EFI} $EFI_DIR
	mount -t auto /dev/${DISK_DEFAULT}${PARTED_SYS} $SYS_DIR
	sleep 1
	sed -i "/\[multilib\]/,/Include/"'s/^#//' ${SYS_DIR}/etc/pacman.conf
	pacman -Sy
	fast_install3
}

fast_install3() {
	pacman-key --init
	pacstrap -K $SYS_DIR $p_base $p_drv $p_font || exit
	genfstab -L $SYS_DIR >> $SYS_DIR/etc/fstab || exit
	mkinitcpio -p linux || exit
	system_settings
}

pre_reboot() {
cat > $SYS_DIR/root/post << ENDOFILE
#!/usr/bin/env bash
add_user=""
pass_root=""
pass_user=""
hostname="arch"

echo -e $GREEN"...Настройка сиситемы..."
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
echo "KEYMAP=us,ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf
locale-gen
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc --utc && date
echo $hostname > /etc/hostname
systemctl enable NetworkManager
echo -e $ORANGE"...Настройка пользователя..."
echo "Введите имя пользователя"
read -p '>>' add_user
useradd -m -s /bin/bash $add_user
usermod -aG audio,video,input,disk,storage,optical,wheel,adm,ftp,log,sys,uucp $add_user
echo -e "Введите пароль для root"
read -p '>>' pass_root
echo -e "$pass_root\n$pass_root" | passwd -q root
echo -e "Введите пароль для $user"
read -p '>>' pass_user
echo -e "$pass_user\n$pass_user" | passwd -q $add_user
echo -e $GREEN"Настройка завершена!"
sleep 1
cp $SYS_DIR/usr/lib/systemd/system/getty@.service $SYS_DIR/etc/systemd/system/autologin@.service
ln -s $SYS_DIR/etc/systemd/system/autologin@.service $SYS_DIR/etc/systemd/system/getty.target.wants/getty@tty1.service
hwclock --systohc --utc && date
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
pacman -Syu --noconfirm grub efibootmgr dosfstools os-prober
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Arch --force
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
ENDOFILE
chmod +x $SYS_DIR/root/post
}

system_settings() {
	pre_reboot
	echo -e $GREEN"Базовая система установленна!"
	echo -e $ORANGE"Дальнейшая настройка будет производится в chroot"
	echo -e $GREEN"Нажмите Enter, чтобы продолжить"
	read
	echo -e $GREEN"Переход в chroot..."
	sleep 5
	arch-chroot $SYS_DIR /bin/bash -c "/root/post" || exit
	acrh-chroot $SYS_DIR /bin/bash
}
fast_install
