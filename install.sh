#!/bin/sh
# Copyright Amazon.com, Inc. or its affiliates.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#
#  1. Redistributions of source code must retain the above copyright notice,
#  this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright
#  notice, this list of conditions and the following disclaimer in the
#  documentation and/or other materials provided with the distribution.
#
#  3. Neither the name of the copyright holder nor the names of its
#  contributors may be used to endorse or promote products derived from
#  this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
#  BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
#  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
#  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
#  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
#  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
#  IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.

set -e
set -x

USAGE=$(cat <<EOF
Install Amazon EBS Autoscale

    $0 [options] -m <mount-point>

Options

    -d, --initial-device DEVICE
                        Initial device to use for mountpoint - e.g. /dev/xvdba.
                        (Default: none - automatically create and attaches a volume)
                        If provided --initial-size is ignored.

    -f, --file-system   btrfs | lvm.ext4
                        Filesystem to use (default: btrfs).
                        Options are btrfs or lvm.ext4

    -m, --mountpoint    MOUNTPOINT
                        Mount point for autoscale volume (default: /scratch)

    -s, --initial-size  SIZE
                        Initial size of the volume in GB. (Default: 100)
                        Only used if --initial-device is NOT specified.

EOF
)

if [ "$#" -lt "1" ]; then
  echo "$USAGE"
  exit 1
fi

MOUNTPOINT=/scratch
SIZE=100
DEVICE=""
FILE_SYSTEM=btrfs
BASEDIR=$(dirname $0)

. ${BASEDIR}/shared/utils.sh

initialize

# parse options
PARAMS=""
while (( "$#" )); do
    case "$1" in
        -s|--initial-size)
            SIZE=$2
            shift 2
            ;;
        -d|--initial-device)
            DEVICE=$2
            shift 2
            ;;
        -f|--file-system)
            FILE_SYSTEM=$2
            shift 2
            ;;
        -m|--mountpoint)
            MOUNTPOINT=$2
            shift 2
            ;;
        --) # end parsing
            shift
            break
            ;;
        -*|--*=)
            error "unsupported argument $1"
            ;;
        *) # positional arguments
            PARAMS="$PARAMS $1"
            shift
            ;;
    esac
done

eval set -- "$PARAMS"


# Install executables
# make executables available on standard PATH
mkdir -p /usr/local/amazon-ebs-autoscale/{bin,shared}
cp ${BASEDIR}/bin/{create-ebs-volume,ebs-autoscale} /usr/local/amazon-ebs-autoscale/bin
chmod +x /usr/local/amazon-ebs-autoscale/bin/*
ln -sf /usr/local/amazon-ebs-autoscale/bin/* /usr/local/bin/
ln -sf /usr/local/amazon-ebs-autoscale/bin/* /usr/bin/


# copy shared assets
cp ${BASEDIR}/shared/utils.sh /usr/local/amazon-ebs-autoscale/shared


## Install configs
# install the logrotate config
cp ${BASEDIR}/config/ebs-autoscale.logrotate /etc/logrotate.d/ebs-autoscale

# install default config
cat ${BASEDIR}/config/ebs-autoscale.json | \
  sed -e "s#%%MOUNTPOINT%%#${MOUNTPOINT}#" | \
  sed -e "s#%%FILESYSTEM%%#${FILE_SYSTEM}#" \
  > /etc/ebs-autoscale.json

## Create filesystem
if [ -e $MOUNTPOINT ] && ! [ -d $MOUNTPOINT ]; then
  echo "ERROR: $MOUNTPOINT exists but is not a directory."
  exit 1
elif ! [ -e $MOUNTPOINT ]; then
  mkdir -p $MOUNTPOINT
fi

# If a device is not given, or if the device is not valid
if [ -z "${DEVICE}" ] || [ ! -b "${DEVICE}" ]; then
  DEVICE=$(create-ebs-volume --size $SIZE)
fi

# create and mount the BTRFS filesystem
if [ "${FILE_SYSTEM}" = "btrfs" ]; then
  mkfs.btrfs -f -d single $DEVICE
  mount $DEVICE $MOUNTPOINT
  # add entry to fstab
  # allows non-root users to mount/unmount the filesystem
  echo -e "${DEVICE}\t${MOUNTPOINT}\tbtrfs\tdefaults\t0\t0" |  tee -a /etc/fstab
elif [ "${FILE_SYSTEM}" = "lvm.ext4" ]; then
  VG=$(get_config_value .lvm.volume_group)
  LV=$(get_config_value .lvm.logical_volume)
  pvcreate $DEVICE
  vgcreate $VG $DEVICE
  lvcreate $VG -n $LV -l 100%VG
  mkfs.ext4 /dev/mapper/${VG}-${LV}
  mount /dev/mapper/${VG}-${LV} $MOUNTPOINT
  echo -e "/dev/mapper/${VG}-${LV}\t${MOUNTPOINT}\text4\tdefaults\t0\t0" |  tee -a /etc/fstab
else
  echo "Unknown file system type: ${FILE_SYSTEM}"
  exit 1
fi
chmod 1777 ${MOUNTPOINT}

## Install service
INIT_SYSTEM=$(detect_init_system 2>/dev/null)
case $INIT_SYSTEM in
  upstart|systemd)
    echo "$INIT_SYSTEM detected"
    cd ${BASEDIR}/service/$INIT_SYSTEM
    . ./install.sh
    ;;

  *)
    echo "Could not install EBS Autoscale - unsupported init system"
    exit 1
esac
cd ${BASEDIR}
