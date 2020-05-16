#!/bin/bash

initctl stop ebs-autoscale

# uninstall the upstart config
rm /etc/init/ebs-autoscale.conf

# deregister the ebs-autoscale upstart conf
initctl reload-configuration
