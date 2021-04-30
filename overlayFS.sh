get_bootro_now() {
 findmnt /boot | grep -q " ro,"
}

get_overlay_now() {
  grep -q "boot=overlay" /proc/cmdline
}

get_overlay_conf() {
  grep -q "boot=overlay" /boot/cmdline.txt
}

get_bootro_now() {
 findmnt /boot | grep -q " ro,"
}

get_bootro_conf() {
  grep /boot /etc/fstab | grep -q "defaults.*,ro "
}

is_uname_current() {
  test -d "/lib/modules/$(uname -r)"
  return $?
}

enable_bootro() {
  if get_overlay_now ; then
    echo "Overlay in use; cannot update fstab"
    return 1
  fi
  sed -i /etc/fstab -e "s/\(.*\/boot.*\)defaults\(.*\)/\1defaults,ro\2/"
}

disable_bootro() {
  if get_overlay_now ; then
    echo "Overlay in use; cannot update fstab"
    return 1
  fi
  sed -i /etc/fstab -e "s/\(.*\/boot.*\)defaults,ro\(.*\)/\1defaults\2/"
}

enable_overlayfs() {
  KERN=$(uname -r)
  INITRD=initrd.img-"$KERN"-overlay

  # mount the boot partition as writable if it isn't already
  if get_bootro_now ; then
    if ! mount -o remount,rw /boot 2>/dev/null ; then
      echo "Unable to mount boot partition as writable - cannot enable"
      return 1
    fi
    BOOTRO=yes
  else
    BOOTRO=no
  fi

  cat > /etc/initramfs-tools/scripts/overlay << 'EOF'
# Local filesystem mounting			-*- shell-script -*-

#
# This script overrides local_mount_root() in /scripts/local
# and mounts root as a read-only filesystem with a temporary (rw)
# overlay filesystem.
#

. /scripts/local

local_mount_root()
{
	local_top
	local_device_setup "${ROOT}" "root file system"
	ROOT="${DEV}"

	# Get the root filesystem type if not set
	if [ -z "${ROOTFSTYPE}" ]; then
		FSTYPE=$(get_fstype "${ROOT}")
	else
		FSTYPE=${ROOTFSTYPE}
	fi

	local_premount

	# CHANGES TO THE ORIGINAL FUNCTION BEGIN HERE
	# N.B. this code still lacks error checking

	modprobe ${FSTYPE}
	checkfs ${ROOT} root "${FSTYPE}"

	# Create directories for root and the overlay
	mkdir /lower /upper

	# Mount read-only root to /lower
	if [ "${FSTYPE}" != "unknown" ]; then
		mount -r -t ${FSTYPE} ${ROOTFLAGS} ${ROOT} /lower
	else
		mount -r ${ROOTFLAGS} ${ROOT} /lower
	fi

	modprobe overlay || insmod "/lower/lib/modules/$(uname -r)/kernel/fs/overlayfs/overlay.ko"

	# Mount a tmpfs for the overlay in /upper
	mount -t tmpfs tmpfs /upper
	mkdir /upper/data /upper/work

	# Mount the final overlay-root in $rootmnt
	mount -t overlay \
	    -olowerdir=/lower,upperdir=/upper/data,workdir=/upper/work \
	    overlay ${rootmnt}
}
EOF

  # add the overlay to the list of modules
  if ! grep overlay /etc/initramfs-tools/modules > /dev/null; then
    echo overlay >> /etc/initramfs-tools/modules
  fi

  # build the new initramfs
  update-initramfs -c -k "$KERN"

  # rename it so we know it has overlay added
  mv /boot/initrd.img-"$KERN" /boot/"$INITRD"

  # there is now a modified initramfs ready for use...

  # modify config.txt
  sed -i /boot/config.txt -e "/initramfs.*/d" 
  echo initramfs "$INITRD" >> /boot/config.txt

  # modify command line
  if ! grep -q "boot=overlay" /boot/cmdline.txt ; then
      sed -i /boot/cmdline.txt -e "s/^/boot=overlay /"
  fi

  if [ "$BOOTRO" = "yes" ] ; then
    if ! mount -o remount,ro /boot 2>/dev/null ; then
        echo "Unable to remount boot partition as read-only"
    fi
  fi
}


disable_overlayfs() {
  KERN=$(uname -r)
  # mount the boot partition as writable if it isn't already
  if get_bootro_now ; then
    if ! mount -o remount,rw /boot 2>/dev/null ; then
      echo "Unable to mount boot partition as writable - cannot disable"
      return 1
    fi
    BOOTRO=yes
  else
    BOOTRO=no
  fi

  # modify config.txt
  sed -i /boot/config.txt -e "/initramfs.*/d"
  update-initramfs -d -k "${KERN}-overlay"

  # modify command line
  sed -i /boot/cmdline.txt -e "s/\(.*\)boot=overlay \(.*\)/\1\2/"

  if [ "$BOOTRO" = "yes" ] ; then
    if ! mount -o remount,ro /boot 2>/dev/null ; then
        echo "Unable to remount boot partition as read-only"
    fi
  fi
}

do_overlayfs() {
  DEFAULT=--defaultno
  CURRENT=0
  STATUS="disabled"

  if ! is_uname_current; then
    echo "Could not find modules for the running kernel ($(uname -r))."
    return 1
  fi

  if get_overlay_conf; then
    DEFAULT=
    CURRENT=1
    STATUS="enabled"
  fi


  if [ $OVERLAY -eq $CURRENT ]; then
    if [ $OVERLAY -eq 0 ]; then
      if enable_overlayfs; then
        STATUS="enabled"
        ASK_TO_REBOOT=1
      else
        STATUS="unchanged"
      fi
    elif [ $OVERLAY -eq 1 ]; then
      if disable_overlayfs; then
        STATUS="disabled"
        echo "$STATUS"
        ASK_TO_REBOOT=1
      else
        STATUS="unchanged"
      fi
    else
      return $OVERLAY
    fi
  fi
  echo "The overlay file system is $STATUS."

  if get_overlay_now ; then
    if get_bootro_conf; then
      BPRO="read-only"
    else
      BPRO="writable"
    fi
    echo "The boot partition is currently $BPRO. This cannot be changed while an overlay file system is enabled."
  else
    DEFAULT=--defaultno
    CURRENT=0
    STATUS="writable"
    if get_bootro_conf; then
      DEFAULT=
      CURRENT=1
      STATUS="read-only"
    fi

    if [ $READONLY=$CURRENT ]; then
      if [ $READONLY=0 ]; then
        if enable_bootro; then
          STATUS="read-only"
          ASK_TO_REBOOT=1
        else
          STATUS="unchanged"
        fi
      elif [ $READONLY=1 ]; then
        if disable_bootro; then
          STATUS="writable"
          ASK_TO_REBOOT=1
        else
          STATUS="unchanged"
        fi
      else
        return $READONLY
      fi
    fi
    
  fi
  echo "The boot partition is $STATUS."
}

while getopts ":o:b:" opt; do
  case $opt in
    o) overlayfs="$OPTARG"
    ;;
    b) readonlyboot="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG . -o y/n for overlay fs and -b y/n for read only boot" >&2
    ;;
  esac
done

case $overlayfs in
        y)
                echo "Trying to enable Overlay FS"
                OVERLAY=0
                ;;
        n)
                echo "Trying to disable Overlay FS"
                OVERLAY=1
                ;;
        *)
esac

case $readonlyboot in
        y)
                echo "Trying to enable Read Only Boot"
                READONLY=0
                ;;
        n)
                echo "Trying to disable Read Only Boot"
                READONLY=1
                ;;
        *)
esac


do_overlayfs