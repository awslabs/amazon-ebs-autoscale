#!/bin/bash

systemctl stop ebs-autoscale.service
systemctl disable ebs-autoscale.service

# uninstall systemd service
rm /usr/lib/systemd/system/ebs-autoscale.service

# update daemon config
systemctl daemon-reload
