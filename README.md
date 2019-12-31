# Amazon Elastic Block Store Autoscale

This is an example of a daemon process that monitors a BTRFS filesystem mountpoint and automatically expands it when free space falls below a configured threshold. New [Amazon EBS](https://aws.amazon.com/ebs/) volumes are added to the instance as necessary and the underlying [BTRFS filesystem](http://btrfs.wiki.kernel.org) expands while still mounted. As new devices are added, the BTRFS metadata blocks are rebalanced to mitigate the risk that space for metadata will not run out.

## Assumptions:

1. Code is running on an AWS EC2 instance
2. The instance is using a Linux based OS with either **upstart** or **systemd** system initialization
3. The instance has a IAM Instance Profile with appropriate permissions to create and attach new EBS volumes. See the [IAM Instance Profile](#iam_instance_profile) section below for more details
4. That prerequisites are installed on the instance.

Provided in this repo are:

1. A python [script](bin/create-ebs-volume.py) that creates and attaches new EBS volumes to the current instance
2. The daemon [script](bin/ebs-autoscale) that monitors disk space and expands the BTRFS filesystem by leveraging the above script to add EBS volumes, expand the filesystem, and rebalance the metadata blocks
3. Service definitions for [upstart](service/upstart/ebs-autoscale.conf) and [systemd](service/systemd/ebs-autoscale.service)
4. Configuration files for the [service](config/ebs-autoscale.json) and [logrotate](config/ebs-autoscale.logrotate)
5. An [installation script](install.sh) to configure and install all of the above
6. An example [cloud-init](templates/cloud-init-userdata.yaml) script that can be used as EC2 instance user-data for automated installation

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

that installs required packages and runs the initialization script. By default this creates a mount point of `/scratch` on a encrypted 20GB EBS volume. To change the mount point, edit the file.

## A note on IAM Instance Profile

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
                "ec2:ModifyInstanceAttribute",
                "ec2:DescribeVolumeAttribute",
                "ec2:CreateVolume",
                "ec2:DeleteVolume"
            ],
            "Resource": "*"
        }
    ]
}
```

## License Summary

This sample code is made available under the MIT license. 
