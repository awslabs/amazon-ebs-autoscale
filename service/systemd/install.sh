#!/bin/bash

# install systemd service
cp ebs-autoscale.service /etc/systemd/ebs-autoscale.service

# enable the service and start
systemctl daemon-reload
systemctl enable ebs-autoscale.service
systemctl start ebs-autoscale.service