#!/bin/bash

# install the upstart config
cp ebs-autoscale.conf /etc/init/ebs-autoscale.conf

# Register the ebs-autoscale upstart conf and start the service
initctl reload-configuration
initctl start ebs-autoscale