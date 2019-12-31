#!/bin/bash

# install systemd service
cp ebs-autoscale.service /usr/lib/systemd/system/ebs-autoscale.service

# enable the service and start
systemctl daemon-reload
systemctl enable ebs-autoscale.service
systemctl start ebs-autoscale.service