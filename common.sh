#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# Functions:
# compile_uboot
# compile_sunxi_tools
# compile_kernel
# install_external_applications
# write_uboot

compile_uboot (){
#---------------------------------------------------------------------------------------------------------------------------------
# Compile uboot from sources
#---------------------------------------------------------------------------------------------------------------------------------
if [ -d "$SOURCES/$BOOTSOURCEDIR" ]; then
	
	local branch="${BRANCH//default/}"
	[[ -n "$branch" ]] && branch="-"$branch	
		
	display_alert "Compiling uboot. Please wait." "$VER" "info"
	echo `date +"%d.%m.%Y %H:%M:%S"` $SOURCES/$BOOTSOURCEDIR/$BOOTCONFIG >> $DEST/debug/install.log 
	cd $SOURCES/$BOOTSOURCEDIR
	make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	
	# there are two methods of compilation
	if [[ $BOOTCONFIG == *config* ]]; then
	
		make $CTHREADS $BOOTCONFIG CROSS_COMPILE=arm-linux-gnueabihf- >/dev/null 2>&1
		[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
		[ -f .config ] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config			
		[ -f $SOURCES/$BOOTSOURCEDIR/tools/logos/udoo.bmp ] && cp $SRC/lib/bin/armbian-u-boot.bmp $SOURCES/$BOOTSOURCEDIR/tools/logos/udoo.bmp
		touch .scmversion
		
		# special compilation for armada
		[[ $LINUXFAMILY == "marvell" ]] && local MAKEPARA="u-boot.mmc"
		
		# patch mainline uboot configuration to boot with old kernels
		if [[ $BRANCH == "default" && $LINUXFAMILY == sun*i ]] ; then
			if [ "$(cat $SOURCES/$BOOTSOURCEDIR/.config | grep CONFIG_ARMV7_BOOT_SEC_DEFAULT=y)" == "" ]; then
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $SOURCES/$BOOTSOURCEDIR/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $SOURCES/$BOOTSOURCEDIR/.config
			fi
		fi	
		
		eval 'make $MAKEPARA $CTHREADS CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-" 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." 20 80'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	else
		eval 'make $MAKEPARA $CTHREADS $BOOTCONFIG CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-" 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." 20 80'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	fi


	# create .deb package

	CHOOSEN_UBOOT="linux-u-boot"$branch"-"$BOARD"_"$REVISION"_armhf"
	UBOOT_PCK="linux-u-boot-"$BOARD""$branch
	mkdir -p $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT $DEST/debs/$CHOOSEN_UBOOT/DEBIAN
	
# set up post install script
cat <<END > $DEST/debs/$CHOOSEN_UBOOT/DEBIAN/postinst
#!/bin/bash
set -e
if [[ \$DEVICE == "" ]]; then DEVICE="/dev/mmcblk0"; fi

if [[ \$DPKG_MAINTSCRIPT_PACKAGE == *cubox* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/SPL of=\$DEVICE bs=512 seek=2 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot.img of=\$DEVICE bs=1K seek=42 status=noxfer ) > /dev/null 2>&1	
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *guitar* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/bootloader.bin of=\$DEVICE bs=512 seek=4097 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot-dtb.bin of=\$DEVICE bs=512 seek=6144 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroid* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/bl1.bin.hardkernel of=\$DEVICE seek=1 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/bl2.bin.hardkernel of=\$DEVICE seek=31 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot.bin of=\$DEVICE bs=512 seek=63 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/tzsw.bin.hardkernel of=\$DEVICE seek=719 conv=fsync ) > /dev/null 2>&1
	( dd if=/dev/zero of=\$DEVICE seek=1231 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *udoo* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/SPL of=\$DEVICE bs=1k seek=1 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot.img of=\$DEVICE bs=1K seek=69 status=noxfer ) > /dev/null 2>&1		
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *armada* ]] ; then 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot.mmc of=\$DEVICE bs=512 seek=1 status=noxfer ) > /dev/null 2>&1	
else 
	( dd if=/usr/lib/$CHOOSEN_UBOOT/u-boot-sunxi-with-spl.bin of=\$DEVICE bs=1024 seek=8 status=noxfer ) > /dev/null 2>&1	
fi
exit 0
END
#

chmod 755 $DEST/debs/$CHOOSEN_UBOOT/DEBIAN/postinst
# set up control file
cat <<END > $DEST/debs/$CHOOSEN_UBOOT/DEBIAN/control
Package: linux-u-boot-$BOARD$branch
Version: $REVISION
Architecture: armhf
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Uboot loader $VER
END
#

	# copy proper uboot files to place
	if [[ $BOARD == cubox-i* ]] ; then
		[ ! -f "SPL" ] || cp SPL u-boot.img $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT		
	elif [[ $BOARD == guitar* ]] ; then
		[ ! -f "u-boot-dtb.bin" ] || cp u-boot-dtb.bin $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT	
		[ ! -f "$SRC/lib/bin/s500-bootloader.bin" ] || cp $SRC/lib/bin/s500-bootloader.bin $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT/bootloader.bin
	elif [[ $BOARD == odroid* ]] ; then	
		[ ! -f "sd_fuse/hardkernel/bl1.bin.hardkernel" ] || cp sd_fuse/hardkernel/bl1.bin.hardkernel $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT	
		[ ! -f "sd_fuse/hardkernel/bl2.bin.hardkernel" ] || cp sd_fuse/hardkernel/bl2.bin.hardkernel $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
		[ ! -f "sd_fuse/hardkernel/tzsw.bin.hardkernel" ] || cp sd_fuse/hardkernel/tzsw.bin.hardkernel $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
		[ ! -f "u-boot.bin" ] || cp u-boot.bin $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT/
	elif [[ $BOARD == udoo* ]] ; then
		[ ! -f "u-boot.img" ] || cp SPL u-boot.img $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
	elif [[ $BOARD == armada* ]] ; then
		[ ! -f "u-boot.mmc" ] || cp u-boot.mmc $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT
	else
		[ ! -f "u-boot-sunxi-with-spl.bin" ] || cp u-boot-sunxi-with-spl.bin $DEST/debs/$CHOOSEN_UBOOT/usr/lib/$CHOOSEN_UBOOT 
	fi

	cd $DEST/debs
	display_alert "Target directory" "$DEST/debs/" "info"
	display_alert "Building deb" "$CHOOSEN_UBOOT.deb" "info"
	dpkg -b $CHOOSEN_UBOOT >/dev/null 2>&1
	rm -rf $CHOOSEN_UBOOT
	CHOOSEN_UBOOT=$CHOOSEN_UBOOT".deb"

	FILESIZE=$(wc -c $DEST/debs/$CHOOSEN_UBOOT | cut -f 1 -d ' ')

	if [[ $FILESIZE -lt 50000 ]]; then
		display_alert "Building failed, check configuration." "$CHOOSEN_UBOOT deleted" "err"
		rm $DEST/debs/$CHOOSEN_UBOOT
		exit
	fi
	
	else
		display_alert "Source file $1 does not exists. Check fetch_from_github configuration." "" "err"
fi
}

compile_sunxi_tools (){
#---------------------------------------------------------------------------------------------------------------------------------
# https://github.com/linux-sunxi/sunxi-tools Tools to help hacking Allwinner devices
#---------------------------------------------------------------------------------------------------------------------------------

	display_alert "Compiling sunxi tools" "@host & target" "info"
	cd $SOURCES/$MISC1_DIR
	make -s clean >/dev/null 2>&1
	rm -f sunxi-fexc sunxi-nand-part
	make -s >/dev/null 2>&1
	cp fex2bin bin2fex /usr/local/bin/
	# make -s clean >/dev/null 2>&1
	# rm -f sunxi-fexc sunxi-nand-part meminfo sunxi-fel sunxi-pio 2>/dev/null
	# make $CTHREADS 'sunxi-nand-part' CC=arm-linux-gnueabihf-gcc >> $DEST/debug/install.log 2>&1
	# make $CTHREADS 'sunxi-fexc' CC=arm-linux-gnueabihf-gcc >> $DEST/debug/install.log 2>&1
	# make $CTHREADS 'meminfo' CC=arm-linux-gnueabihf-gcc >> $DEST/debug/install.log 2>&1

}


compile_kernel (){
#---------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#---------------------------------------------------------------------------------------------------------------------------------

if [ -d "$SOURCES/$LINUXSOURCEDIR" ]; then 

	local branch="${BRANCH//default/}"
	[[ -n "$branch" ]] && branch="-"$branch	
	
	# read kernel version to variable $VER
	grab_version "$SOURCES/$LINUXSOURCEDIR"	

	display_alert "Compiling $BRANCH kernel" "@host" "info"
	cd $SOURCES/$LINUXSOURCEDIR/

	# adding custom firmware to kernel source
	if [[ -n "$FIRMWARE" ]]; then unzip -o $SRC/lib/$FIRMWARE -d $SOURCES/$LINUXSOURCEDIR/firmware; fi

	# use proven config
	if [ "$KERNEL_KEEP_CONFIG" != "yes" ] || [ ! -f $SOURCES/$LINUXSOURCEDIR/.config ]; then
		if [ -f $SRC/userpatches/$LINUXCONFIG.config ]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			cp $SRC/userpatches/$LINUXCONFIG.config $SOURCES/$LINUXSOURCEDIR/.config
		else
			display_alert "Using kernel config file" "lib/config/$LINUXCONFIG.config" "info"
			cp $SRC/lib/config/$LINUXCONFIG.config $SOURCES/$LINUXSOURCEDIR/.config
		fi
	fi

	# hacks for banana family
	if [[ $LINUXFAMILY == "banana" ]] ; then
		sed -i 's/CONFIG_GMAC_CLK_SYS=y/CONFIG_GMAC_CLK_SYS=y\nCONFIG_GMAC_FOR_BANANAPI=y/g' .config
	fi

	# hack for deb builder. To pack what's missing in headers pack.
	cp $SRC/lib/patch/misc/headers-debian-byteshift.patch /tmp

	export LOCALVERSION="-"$LINUXFAMILY

	# We can use multi threading here but not later since it's not working. This way of compilation is much faster. 
	if [ "$KERNEL_CONFIGURE" != "yes" ]; then
		if [ "$BRANCH" = "default" ]; then
			make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- silentoldconfig
		else
			make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig			
		fi
	else
		make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig
		make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
	fi

eval 'make $CTHREADS ARCH=arm CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-" zImage modules 2>&1' \
	${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
	${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling kernel..." 20 80'} \
	${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

if [ ${PIPESTATUS[0]} -ne 0 ] || [ ! -f arch/arm/boot/zImage ]; then
		display_alert "Kernel was not built" "@host" "err"
	    exit 1
fi
eval 'make $CTHREADS ARCH=arm CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-" dtbs 2>&1' \
	${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
	${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling Device Tree..." 20 80'} \
	${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

if [ ${PIPESTATUS[0]} -ne 0 ]; then
		display_alert "DTBs was not build" "@host" "err"
	    exit 1
fi


# different packaging for 4.3+ // probably temporaly soution
KERNEL_PACKING="deb-pkg"
IFS='.' read -a array <<< "$VER"
if (( "${array[0]}" == "4" )) && (( "${array[1]}" >= "3" )); then
KERNEL_PACKING="bindeb-pkg"
fi

# make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- 
# produce deb packages: image, headers, firmware, libc
eval 'make -j1 $KERNEL_PACKING KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$LINUXFAMILY KBUILD_DEBARCH=armhf ARCH=arm DEBFULLNAME="$MAINTAINER" \
	DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE="$CCACHE arm-linux-gnueabihf-" 2>&1 ' \
	${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
	${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Creating kernel packages..." 20 80'} \
	${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}


# we need a name
CHOOSEN_KERNEL=linux-image"$branch"-"$CONFIG_LOCALVERSION$LINUXFAMILY"_"$REVISION"_armhf.deb
cd ..
mv *.deb $DEST/debs/ || exit
else
display_alert "Source file $1 does not exists. Check fetch_from_github configuration." "" "err"
exit
fi
sync
}


install_external_applications (){
#--------------------------------------------------------------------------------------------------------------------------------
# Install external applications example
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Installing external applications" "USB redirector" "info"
# USB redirector tools http://www.incentivespro.com
cd $SOURCES
wget -q http://www.incentivespro.com/usb-redirector-linux-arm-eabi.tar.gz
tar xfz usb-redirector-linux-arm-eabi.tar.gz
rm usb-redirector-linux-arm-eabi.tar.gz
cd $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd
# patch to work with newer kernels
sed -e "s/f_dentry/f_path.dentry/g" -i usbdcdev.c
make -j1 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNELDIR=$SOURCES/$LINUXSOURCEDIR/ >> $DEST/debug/install.log
# configure USB redirector
sed -e 's/%INSTALLDIR_TAG%/\/usr\/local/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%PIDFILE_TAG%/\/var\/run\/usbsrvd.pid/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
sed -e 's/%STUBNAME_TAG%/tusbd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1
sed -e 's/%DAEMONNAME_TAG%/usbsrvd/g' $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd1 > $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
chmod +x $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd
# copy to root
cp $SOURCES/usb-redirector-linux-arm-eabi/files/usb* $DEST/cache/sdcard/usr/local/bin/ 
cp $SOURCES/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $DEST/cache/sdcard/usr/local/bin/ 
cp $SOURCES/usb-redirector-linux-arm-eabi/files/rc.usbsrvd $DEST/cache/sdcard/etc/init.d/
# not started by default ----- update.rc rc.usbsrvd defaults
# chroot $DEST/cache/sdcard /bin/bash -c "update-rc.d rc.usbsrvd defaults"

# some aditional stuff. Some driver as example
if [[ -n "$MISC3_DIR" ]]; then
	display_alert "Installing external applications" "RT8192 driver" "info"
	# https://github.com/pvaret/rtl8192cu-fixes
	cd $SOURCES/$MISC3_DIR
	#git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	(make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KSRC=$SOURCES/$LINUXSOURCEDIR/ >/dev/null 2>&1)
	cp *.ko $DEST/cache/sdcard/usr/local/bin
	#cp blacklist*.conf $DEST/cache/sdcard/etc/modprobe.d/
fi

# MISC4 = NOTRO DRIVERS / special handling

# MISC5 = sunxi display control
if [[ -n "$MISC5_DIR" && $BRANCH != "next" && $LINUXSOURCEDIR == *sunxi* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	cp "$SOURCES/$LINUXSOURCEDIR/include/video/sunxi_disp_ioctl.h" .
	make clean >/dev/null 2>&1
	(make ARCH=arm CC=arm-linux-gnueabihf-gcc KSRC="$SOURCES/$LINUXSOURCEDIR/" >/dev/null 2>&1)
	install -m 755 a10disp "$DEST/cache/sdcard/usr/local/bin"
fi
# MISC5 = sunxi display control / compile it for sun8i just in case sun7i stuff gets ported to sun8i and we're able to use it
if [[ -n "$MISC5_DIR" && $BRANCH != "next" && $LINUXSOURCEDIR == *sun8i* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	wget -q "https://raw.githubusercontent.com/linux-sunxi/linux-sunxi/sunxi-3.4/include/video/sunxi_disp_ioctl.h"
	make clean >/dev/null 2>&1
	(make ARCH=arm CC=arm-linux-gnueabihf-gcc KSRC="$SOURCES/$LINUXSOURCEDIR/" >/dev/null 2>&1)
	install -m 755 a10disp "$DEST/cache/sdcard/usr/local/bin"
fi

# MT7601U
if [[ -n "$MISC6_DIR" && $BRANCH != "next" ]]; then
	display_alert "Installing external applications" "MT7601U - driver" "info"
	cd $SOURCES/$MISC6_DIR
	cat >> fix_build.patch << _EOF_
diff --git a/src/dkms.conf b/src/dkms.conf
new file mode 100644
index 0000000..7563b5a
--- /dev/null
+++ b/src/dkms.conf
@@ -0,0 +1,8 @@
+PACKAGE_NAME="mt7601-sta-dkms"
+PACKAGE_VERSION="3.0.0.4"
+CLEAN="make clean"
+BUILT_MODULE_NAME[0]="mt7601Usta"
+BUILT_MODULE_LOCATION[0]="./os/linux/"
+DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
+AUTOINSTALL=yes
+MAKE[0]="make -j4 KERNELVER=\$kernelver"
diff --git a/src/include/os/rt_linux.h b/src/include/os/rt_linux.h
index 3726b9e..b8be886 100755
--- a/src/include/os/rt_linux.h
+++ b/src/include/os/rt_linux.h
@@ -279,7 +279,7 @@ typedef struct file* RTMP_OS_FD;
 
 typedef struct _OS_FS_INFO_
 {
-#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,12,0)
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,4,0)
 	uid_t				fsuid;
 	gid_t				fsgid;
 #else
diff --git a/src/os/linux/rt_linux.c b/src/os/linux/rt_linux.c
index 1b6a631..c336611 100755
--- a/src/os/linux/rt_linux.c
+++ b/src/os/linux/rt_linux.c
@@ -51,7 +51,7 @@
 #define RT_CONFIG_IF_OPMODE_ON_STA(__OpMode)
 #endif
 
-ULONG RTDebugLevel = RT_DEBUG_TRACE;
+ULONG RTDebugLevel = 0;
 ULONG RTDebugFunc = 0;
 
 #ifdef OS_ABL_FUNC_SUPPORT
_EOF_

	patch -f -s -p1 -r - <fix_build.patch >/dev/null
	cd src
	make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean >/dev/null 2>&1
	(make -s -j4 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LINUX_SRC=$SOURCES/$LINUXSOURCEDIR/ >/dev/null 2>&1)
	cp os/linux/*.ko $DEST/cache/sdcard/lib/modules/$VER-$LINUXFAMILY/kernel/net/wireless/
	mkdir -p $DEST/cache/sdcard/etc/Wireless/RT2870STA
	cp RT2870STA.dat $DEST/cache/sdcard/etc/Wireless/RT2870STA/
	depmod -b $DEST/cache/sdcard/ $VER-$LINUXFAMILY
	make -s clean 1>&2 2>/dev/null
	cd ..
	mkdir -p $DEST/cache/sdcard/usr/src/
	cp -R src $DEST/cache/sdcard/usr/src/mt7601-3.0.0.4
	# TODO: Set the module to build automatically via dkms in the future here

fi

# h3disp for sun8i/3.4.x
if [ "$BOARD" = "orangepiplus" -o "$BOARD" = "orangepih3" ]; then
	install -m 755 "$SRC/lib/scripts/h3disp" "$DEST/cache/sdcard/usr/local/bin"
fi
}

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
write_uboot()
{
	LOOP=$1
	display_alert "Writing bootloader" "$LOOP" "info"
	dpkg -x $DEST"/debs/"$CHOOSEN_UBOOT /tmp/
	CHOOSEN_UBOOT="${CHOOSEN_UBOOT//.deb/}"

	if [[ $BOARD == *cubox* ]] ; then
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/SPL of=$LOOP bs=512 seek=2 status=noxfer >/dev/null 2>&1)
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot.img of=$LOOP bs=1K seek=42 status=noxfer >/dev/null 2>&1)
	elif [[ $BOARD == *armada* ]] ; then
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot.mmc of=$LOOP bs=512 seek=1 status=noxfer >/dev/null 2>&1)		
	elif [[ $BOARD == *udoo* ]] ; then
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/SPL of=$LOOP bs=1k seek=1 status=noxfer >/dev/null 2>&1)
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot.img of=$LOOP bs=1k seek=69 conv=fsync >/dev/null 2>&1)
	elif [[ $BOARD == *guitar* ]] ; then
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/bootloader.bin of=$LOOP bs=512 seek=4097 conv=fsync > /dev/null 2>&1)
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot-dtb.bin of=$LOOP bs=512 seek=6144 conv=fsync > /dev/null 2>&1)
	elif [[ $BOARD == *odroid* ]] ; then
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/bl1.bin.hardkernel of=$LOOP seek=1 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/bl2.bin.hardkernel of=$LOOP seek=31 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot.bin of=$LOOP bs=512 seek=63 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/tzsw.bin.hardkernel of=$LOOP seek=719 conv=fsync ) > /dev/null 2>&1
		( dd if=/dev/zero of=$LOOP seek=1231 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
	else
		( dd if=/tmp/usr/lib/"$CHOOSEN_UBOOT"/u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer >/dev/null 2>&1)
	fi
	if [ $? -ne 0 ]; then
		display_alert "U-boot failed to install" "@host" "err"
		exit 1
	fi
	rm -r /tmp/usr
	sync
}
