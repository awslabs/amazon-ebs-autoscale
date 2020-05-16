#!/bin/bash

set -e

BASEDIR=$(dirname $0)

. ${BASEDIR}/shared/utils.sh
initialize

MOUNTPOINT=$(get_config_value .mountpoint)
instance_id=$(get_metadata instance-id)
availability_zone=$(get_metadata placement/availability-zone)
region=${availability_zone%?}

# stop and uninstall the service
INIT_SYSTEM=$(detect_init_system 2>/dev/null)
case $INIT_SYSTEM in
  upstart|systemd)
    echo "$INIT_SYSTEM detected"
    cd ${BASEDIR}/service/$INIT_SYSTEM
    . ./uninstall.sh
    ;;

  *)
    echo "Could not uninstall EBS Autoscale - unsupported init system"
    exit 1
esac

# unmount the file system
umount $MOUNTPOINT

# detach and delete volumes
attached_volumes=$(
    aws ec2 describe-volumes \
        --region $region \
        --filters "Name=attachment.instance-id,Values=$instance_id"
)

for volume in $attached_volumes; do
    aws ec2 detach-volume --region $region --volume-id $volume
    aws ec2 wait volume-available --region $region --volume-ids $volume
    echo "volume $volume detached"
    
    aws ec2 delete-volume --region $region --volume-id $volume
    aws ec2 wait volume-deleted --region $region --volume-ids $volume
    echo "volume $volume deleted"  
done

