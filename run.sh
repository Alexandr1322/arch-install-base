#!/usr/bin/env bash

setfont ter-u18b
localectl set-locale LANG=ru_RU.UTF-8;
unset LANG;
source /etc/profile.d/locale.sh
#### Переменные
DISK_DEFAULT=""
PARTED_EFI=""
PARTED_SYS=""
EFI_DIR="/mnt/system/boot/efi"
SYS_DIR="/mnt/system"
#### Базовые пакеты
p_base="base base-devel linux-lts linux-firmware amd-ucode intel-ucode xorg networkmanager"
#### Драйвера
p_drv="r8168 nvidia nvidia-utils lib32-nvidia-utils"
#### Шрифты
p_font="ttf-dejavu ttf-liberation ttf-font-awesome ttf-hack ttf-iosevka-nerd"
#### Форматирование текста
bold=$(tput bold)
pt() {
case $2 in
	info) COLOR="94m" ;;
	success) COLOR="92m" ;;
	warning) COLOR="33m" ;;
	yellow) COLOR="93m" ;;
	error) COLOR="31m" ;;
	*) COLOR="0m" ;;
esac
STARTCOLOR="\e[$COLOR";
ENDCOLOR="\e[0m";
    printf "$STARTCOLOR%b$ENDCOLOR" "$1";
}

check_progress() {
if [ $? -eq 0 ]; then
    pt "Статус: OK\n" "success"
else
    pt "Статус: FAIL\n" "error"
    exit
fi
}
####

create_dir() {
if [[ ! -d "$SYS_DIR" ]]; then
	mkdir -p $SYS_DIR
	mkdir -p $EFI_DIR
else
	echo -e "$ORANGE Рабочая директория уже существует!"
fi
}

check_type_disk() {
	if [[ $DISK_DEFAULT == sd* ]]; then
		PARTED_EFI="1" && PARTED_SYS="2"
	fi
	if [[ $DISK_DEFAULT == nvme* ]]; then
		PARTED_EFI="p1" && PARTED_SYS="p2"
	fi
}

fast_install() {
	clear
	pt "<< ВНИМАНИЕ! >>\n" "error"
	pt "Система будет установлена с настройками из готовой конфигурации:\n" "warning"
	pt " - Диск будет размечен автоматически\n" "warning"
	pt "Диск <disk> определяется по NAME <sda,sdb и.т.д>\n" "warning"
	pt "========================================\n" "warning"
	lsblk -o "NAME,MODEL,SIZE"
	pt "========================================\n" "warning"
	pt "Напишите имя диска из списка, на который будет установлена система\n" "info"
	pt "Выйти - 0\n" "info"
	read -p '>> ' DISK_DEFAULT
	if [[ $DISK_DEFAULT = "0" ]]; then cl && exit; fi

	clear
	check_type_disk
	pt "<< Проверьте данные >>\n"
	
	pt "Будьте внимательны, диск будет отформатирован и размечен в GPT\n" "error"
	pt " Диск: <${DISK_DEFAULT}> $(lsblk -o "MODEL,SIZE" /dev/${DISK_DEFAULT} -d -n)\n" "success"
	pt " EFI раздел: <${PARTED_EFI}>\n" "success"
	pt " SYS раздел: <${PARTED_SYS}>\n" "success"
	pt "Все верно? [Y/n]\n" "yellow"
	read -p '>> ' check_finstall

	case $check_install in
		y|Y|д) fast_install2 ;;
		n|N|н) clear && exit ;;
		*) fast_install2 ;;
	esac

}

fast_install2() {
	pt "Размечаем..\n" "yellow"
# Автоматическая разметка
	parted -s /dev/${DISK_DEFAULT} mklabel gpt
	parted -s /dev/${DISK_DEFAULT} mkpart fat32 0% 1024M
	parted -s /dev/${DISK_DEFAULT} set 1 esp on  
	parted -s /dev/${DISK_DEFAULT} mkpart primary 1024M 90%
# Форматирование разделов
	mkfs.fat -F32 /dev/${DISK_DEFAULT}${PARTED_EFI}
	check_progress
	mke2fs -t ext4 -L System -q /dev/${DISK_DEFAULT}${PARTED_SYS}
	check_progress
	cfdisk /dev/${DISK_DEFAULT}
	pt "Монтирование..\n" "yellow"
# Монтирование разделов в папки
	create_dir
	pt "Монтирование EFI\n" "info"
	mount -t auto /dev/${DISK_DEFAULT}${PARTED_EFI} $EFI_DIR
	check_progress
	pt "Монтирование SYSTEM\n" "info"
	mount -t auto /dev/${DISK_DEFAULT}${PARTED_SYS} $SYS_DIR
	check_progress
	sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
	pacman -Sy
	fast_install3
}

fast_install3() {
	pt "Проверяем ключи..\n" "yellow"
	pacman-key --init || exit
	check_progress
	pt "Устанавливаем систему..\n" "yellow"
	pacstrap -K $SYS_DIR $p_base $p_drv $p_font || exit
	check_progress
	pt "Создаем разметку fstab..\n" "yellow"
	genfstab -L $SYS_DIR >> $SYS_DIR/etc/fstab || exit
	check_progress
	system_settings
}

pre_reboot() {
pt "Создаем post скрипт..\n" "yellow"
cat > $SYS_DIR/root/post << ENDOFILE
#!/usr/bin/env bash
#### Форматирование текста
bold=$(tput bold)

pt() {
case $2 in
	info) COLOR="94m" ;;
	success) COLOR="92m" ;;
	warning) COLOR="33m" ;;
	yellow) COLOR="93m" ;;
	error) COLOR="31m" ;;
	*) COLOR="0m" ;;
esac
STARTCOLOR="\e[$COLOR";
ENDCOLOR="\e[0m";
    printf "$STARTCOLOR%b$ENDCOLOR" "$1";
}

check_progress() {
if [ $? -eq 0 ]; then
    pt "Статус: OK\n" "success"
else
    pt "Статус: FAIL\n" "error"
    exit
fi
}
####

sleep 1

pt "...Настройка локали...\n" "yellow"
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
echo "KEYMAP=us,ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf
locale-gen
check_progress

pt "...Настройка пользователя...\n" "yellow"
pt "Введите имя пользователя" "warning"
read -p '>> ' add_user
pt "Создание пользователя...\n" "yellow"
useradd -m -s /bin/bash $add_user
check_progress
pt "Добавление в группы...\n" "yellow"
usermod -aG audio,video,input,disk,storage,optical,wheel,adm,ftp,log,sys,uucp $add_user
check_progress
pt "Введите пароль для root\n" "warning"
read -p '>> ' pass_root
pt "$pass_root\n$pass_root" | passwd -q $root
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
pt "Введите пароль для $user\n" "warning"
read -p '>> ' pass_user
pt "$pass_user\n$pass_user" | passwd -q $add_user
pt "\n==================================="
pt "Ваш пароль для root: \n"$pass_root
pt "Ваш пароль для $user: \n"$pass_user
pt "==================================="
pt "Нажмите Enter, чтобы продолжить\n" "success"
read

pt "Настройка системы...\n" "warning"
echo $hostname > /etc/hostname
systemctl enable NetworkManager
cp /usr/lib/systemd/system/getty@.service /etc/systemd/system/autologin@.service
ln -s /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
hwclock --systohc --utc && date
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
pacman -Syu --noconfirm grub efibootmgr dosfstools os-prober
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch --force
grub-mkconfig -o /boot/grub/grub.cfg || exit
mkinitcpio -P || exit
pt "Настройка системы завершена!\n" "success"

pt "Настройка пользователя завершена!\n" "success"
ENDOFILE
check_progress
chmod +x $SYS_DIR/root/post
}

system_settings() {
	pre_reboot
	pt "Базовая система установленна!\n" "success"
	pt "Дальнейшая настройка будет производится в chroot\n" "warning"
	pt "Нажмите Enter, чтобы продолжить\n" "success"
	read
	pt "Переход в chroot через 5 секунд...\n" "success"
	sleep 5
	arch-chroot $SYS_DIR /bin/bash -c "/root/post"
	acrh-chroot $SYS_DIR /bin/bash
}
fast_install
