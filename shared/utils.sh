#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#
#  1. Redistributions of source code must retain the above copyright notice,
#  this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright
#  notice, this list of conditions and the following disclaimer in the
#  documentation and/or other materials provided with the distribution.
#
#  3. Neither the name of the copyright holder nor the names of its
#  contributors may be used to endorse or promote products derived from
#  this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
#  BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
#  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
#  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
#  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
#  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
#  IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.

function get_metadata() {
    local key=$1
    local metadata_ip='169.254.169.254'

    if [ ! -z "$IMDSV2" ]; then
        local token=$(curl -s -X PUT "http://$metadata_ip/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
        local token_wrapper='-H "X-aws-ec2-metadata-token: $token"'
    fi
    
    echo `curl -s $token_wrapper http://$metadata_ip/latest/meta-data/$key`
}

function initialize() {
    export AWS_AZ=$(get_metadata placement/availability-zone)
    export AWS_REGION=$(echo ${AWS_AZ} | sed -e 's/[a-z]$//')
    export INSTANCE_ID=$(get_metadata instance-id)
    export EBS_AUTOSCALE_CONFIG_FILE=/etc/ebs-autoscale.json
}

function detect_init_system() {
    # detects the init system in use
    # based on the following:
    # https://unix.stackexchange.com/a/164092
    if [[ `/sbin/init --version` =~ upstart ]]; then echo upstart;
    elif [[ `systemctl` =~ -\.mount ]]; then echo systemd;
    elif [[ -f /etc/init.d/cron && ! -h /etc/init.d/cron ]]; then echo sysv-init;
    else echo unknown; fi
}

function get_config_value() {
    local filter=$1

    jq -r $filter $EBS_AUTOSCALE_CONFIG_FILE
}

function logthis() {
    echo "[`date`] $1" >> $(get_config_value .logging.log_file)
}

function starting() {
    logthis "Starting EBS Autoscale"
}

function stopping() {
    logthis "Stopping EBS Autoscale"
}