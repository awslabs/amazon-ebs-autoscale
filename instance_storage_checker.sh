#!/usr/bin/env bash
# Requires awscli, awk, curl
# nvme-cli & mdadm will be installed if needed

set -e

InstanceType=$(curl --silent http://169.254.169.254/latest/meta-data/instance-type)
AvailabilityZone=$(curl --silent http://169.254.169.254/latest/meta-data/placement/availability-zone)
Region=${AvailabilityZone:0:9}

while read -r Architecture StorageTotal StorageDiskSize StorageDiskCount StorageDiskNVME ; do
  echo "-- Checking For instance storage --"
  if [[ $StorageDiskCount -gt 0 ]] ; then
    case $StorageDiskNVME in
        required)
            echo "$StorageDiskCount x $StorageDiskSize GB disks found, Total of $StorageTotal of instance storage, NVME is $StorageDiskNVME. Installing nvme-cli"
            yum install -y -q nvme-cli
            DeviceNames=$(nvme list | awk '/AWS/ { print $1 }')
        ;;
        supported)
            echo "Don't know what to do with $StorageDiskNVME mode"
        ;;
        *)
            for ((disk = 1 ; disk <= StorageDiskCount ; disk++)); do
                ephemeral=$((disk - 1))
                DeviceNames="/dev/$(curl --silent http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral$ephemeral) $DeviceNames"
            done
        ;;
    esac
    echo "Instance Storage Device Path(s):"
    echo $DeviceNames | tr ' ' ','
    if [[ $StorageDiskCount -gt 1 ]] ; then
      echo "Multiple devices, installing mdadm & creating RAID"
      yum install mdadm -y -q
      RAID_DEVICE=/dev/md0
      mdadm --create --verbose $RAID_DEVICE --level=0 --name=Instance_Storage --raid-devices=$StorageDiskCount $DeviceNames
      echo $RAID_DEVICE > instance_storage_device.txt
      echo "Device \"$RAID_DEVICE\" exported to instance_storage_device.txt for EBS Autoscale inital device"     
    else
      echo "$DeviceNames" > instance_storage_device.txt 
      echo "Device \"$DeviceNames\" exported to instance_storage_device.txt for EBS Autoscale inital device" 
    fi
  else
    echo "No instance storage found"
  fi
done < <(aws --region "$Region" --output text ec2 describe-instance-types --instance-types "$InstanceType" \
    --query InstanceTypes[].[ProcessorInfo.SupportedArchitectures[0],InstanceStorageInfo.TotalSizeInGB,InstanceStorageInfo.Disks[0].SizeInGB,InstanceStorageInfo.Disks[0].Count,InstanceStorageInfo.NvmeSupport])