#!/bin/bash

# install the upstart config
sed -e "s#YOUR_MOUNTPOINT#${MOUNTPOINT}#" ebs-autoscale.conf.template > /etc/init/ebs-autoscale.conf

# install the logrotate config
cp ebs-autoscale.logrotate /etc/logrotate.d/ebs-autoscale

# Register the ebs-autoscale upstart conf and start the service
initctl reload-configuration
initctl start ebs-autoscale