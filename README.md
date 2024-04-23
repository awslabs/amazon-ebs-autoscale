:warning: __DEPRECATION NOTICE__ :warning:

THIS REPOSITORY IS DEPRECATED AND WILL BE ARCHIVED ON MAY 17, 2024

This repository is no longer actively maintained and will be archived on May 17, 2024. As archived code, it remains publicly available for historical reference purposes only.

For alternative and fully managed solutions for scalable storage in AWS you should consider:
- [Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/?nc=sn&loc=2)
- [Amazon Elastic File System (Amazon EFS)](https://aws.amazon.com/efs/)

# Amazon Elastic Block Store Autoscale

This is an example of a daemon process that monitors a filesystem mountpoint and automatically expands it when free space falls below a configured threshold. New [Amazon EBS](https://aws.amazon.com/ebs/) volumes are added to the instance as necessary and the underlying filesystem ([BTRFS](http://btrfs.wiki.kernel.org) or [LVM](https://en.wikipedia.org/wiki/Logical_Volume_Manager_(Linux)) with [ext4](https://en.wikipedia.org/wiki/Ext4)) expands as new devices are added.

## Assumptions:

1. Code is running on an AWS EC2 instance
2. The instance and AMI use HVM virtualization
3. The instance AMI allows device names like `/dev/xvdb*` and will not remap them
4. The instance is using a Linux based OS with either **upstart** or **systemd** system initialization
5. The instance has a IAM Instance Profile with appropriate permissions to create and attach new EBS volumes. See the [IAM Instance Profile](#a-note-on-the-iam-instance-profile) section below for more details
6. That prerequisites are installed on the instance:
   1. jq
   2. btrfs-progs
   3. lvm2
   4. unzip

Provided in this repo are:

1. A [script](bin/create-ebs-volume) that creates and attaches new EBS volumes to the current instance
2. A daemon [script](bin/ebs-autoscale) that monitors disk space and expands the targeted filesystem using the above script to add EBS volumes as needed
3. Service definitions for [upstart](service/upstart/ebs-autoscale.conf) and [systemd](service/systemd/ebs-autoscale.service)
4. Configuration files for the [service](config/ebs-autoscale.json) and [logrotate](config/ebs-autoscale.logrotate)
5. An [installation script](install.sh) to configure and install all of the above
6. An [Uninstallation script](uninstall.sh) to remove the service daemon, unmount the filesystem, and detach and delete any ebs volumes created by the daemon
7. An example [cloud-init](templates/cloud-init-userdata.yaml) script that can be used as EC2 instance user-data for automated installation

## Installation

The easiest way to set up an instance is to provide a launch call with the userdata [cloud-init script](templates/cloud-init-userdata.yaml). Here is an example of launching the [Amazon ECS-Optimized AMI](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html) in us-east-1 using this file:

```bash
aws ec2 run-instances --image-id ami-5253c32d \
  --key-name MyKeyPair \
  --user-data file://./templates/cloud-init-userdata.yaml \
  --count 1 \
  --security-group-ids sg-123abc123 \
  --instance-type t2.micro \
  --iam-instance-profile Name=MyInstanceProfileWithProperPermissions
```

that installs required packages and runs the initialization script. By default this creates a mount point of `/scratch` on a encrypted 200GB gp3 EBS volume. To change the mount point, edit the [cloud-init script](templates/cloud-init-userdata.yaml) file and supply additional options to the install script to suit your specific needs.  Install options are shown below.

```text
Install Amazon EBS Autoscale

    install.sh [options] [[-m] <mount-point>]

Options

    -d, --initial-device DEVICE
                        Initial device to use for mountpoint - e.g. /dev/xvdba.
                        (Default: none - automatically create and attaches a volume)
                        If provided --initial-size is ignored.

    -f, --file-system   btrfs | lvm.ext4
                        Filesystem to use (default: btrfs).
                        Options are btrfs or lvm.ext4

    -h, --help
                        Print help and exit.

    -m, --mountpoint    MOUNTPOINT
                        Mount point for autoscale volume (default: /scratch)
                        
    -t, --volume-type   VOLUMETYPE
                        Volume type (default: gp3)

    --volume-iops       VOLUMEIOPS
                        Volume IOPS for gp3, io1, io2 (default: 3000)

    --volume-throughput VOLUMETHROUGHPUT
                        Volume throughput for gp3 (default: 125)

    --min-ebs-volume-size SIZE_GB
                        Mimimum size in GB of new volumes created by the instance.
                        (Default: 150)

    --max-ebs-volume-size SIZE_GB
                        Maximum size in GB of new volumes created by the instance.
                        (Default: 1500)
            
    --max-total-created-size SIZE_GB
                        Maximum total size in GB of all volumes created by the instance.
                        (Default: 8000)
                        
    --max-attached-volumes N
                        Maximum number of attached volumes. (Default: 16)

    --initial-utilization-threshold N
                        Initial disk utilization treshold for scale-up. (Default: 50)

    -s, --initial-size  SIZE_GB
                        Initial size of the volume in GB. (Default: 200)
                        Only used if --initial-device is NOT specified.

    -i, --imdsv2        
                        Enable imdsv2 for instance metadata API requests.
```

## A note on the IAM Instance Profile

In the above, we assume that the `MyInstanceProfileWithProperPermissions` EC2 Instance Profile exists and has the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AttachVolume",
                "ec2:DescribeVolumeStatus",
                "ec2:DescribeVolumes",
                "ec2:DescribeTags",
                "ec2:ModifyInstanceAttribute",
                "ec2:DescribeVolumeAttribute",
                "ec2:CreateVolume",
                "ec2:DeleteVolume",
                "ec2:CreateTags"
            ],
            "Resource": "*"
        }
    ]
}
```

Please note that if you enable EBS encryption and use a Customer Managed Key with AWS Key Management Service, then you should also ensure that you provide [appropriate IAM permissions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html#ebs-encryption-permissions) to use that key.


## A note on the Instance Storage

Here is an example script to leverage instance storage.

```
## Check for instance storage
echo "-- Check for instance storage --"
/opt/amazon-ebs-autoscale/instance_storage_checker.sh 2>&1 >> /var/log/ebs-autoscale-install.log
## Install ebs-autoscale
echo "-- Installing EBS AutoScaler --"
if [ -f instance_storage_device.txt ]; then
    INSTANCE_STORAGE=$(cat instance_storage_device.txt)
    /opt/amazon-ebs-autoscale/install.sh \
    --initial-device $INSTANCE_STORAGE \
    --initial-utilization-threshold 90 \
    --mountpoint /var/lib/docker \
    2>&1 >> /var/log/ebs-autoscale-install.log
else
    /opt/amazon-ebs-autoscale/install.sh \
    —mount point /var/lib/docker 2>&1 >> /var/log/ebs-autoscale-install.log
fi
```


## License Summary

This sample code is made available under the MIT license. 
