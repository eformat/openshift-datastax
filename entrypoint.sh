#!/bin/bash
# -*- mode: sh -*-
#
# Copyright DataStax, Inc, 2017
#   Please review the included LICENSE file for more information.
#

set -e

. /base-checks.sh

link_external_config "${DSE_HOME}"

#create directories for holding the node's data, logs, etc.
mkdir -p /var/lib/spark/worker
mkdir -p /var/lib/spark/rdd
mkdir -p /var/log/spark/worker
mkdir -p /var/log/spark/master

############################################
# Set up variables/configure the image
############################################

IP_ADDRESS="$(hostname --ip-address)"

CASSANDRA_CONFIG="${DSE_HOME}/resources/cassandra/conf/cassandra.yaml"
CASSANDRA_RACK_CONFIG="${DSE_HOME}/resources/cassandra/conf/cassandra-rackdc.properties"

# SNITCH sets the snitch this node will use. Use GossipingPropertyFileSnitch if not set
: ${SNITCH=GossipingPropertyFileSnitch}

# NATIVE_TRANSPORT_ADDRESS is where we listen for drivers/clients to connect to us. Setting to 0.0.0.0 by default is fine
# since we'll be specifying the NATIVE_TRANSPORT_BROADCAST_ADDRESS below
: ${NATIVE_TRANSPORT_ADDRESS='0.0.0.0'}

# LISTEN_ADDRESS is where we listen for other nodes who want to communicate. 'auto' is not a valid value here,
# so use the hostname's IP by default
LISTEN_ADDRESS="$IP_ADDRESS"

# BROADCAST_ADDRESS is where we tell other nodes to communicate with us. Again, 'auto' is not a valid value here,
# so default to the LISTEN_ADDRESS or the hostname's IP address if set to 'auto'
BROADCAST_ADDRESS="${DSE_PORT_9042_TCP_ADDR}"

# By default, tell drivers/clients to use the same address that other nodes are using to communicate with us
: ${NATIVE_TRANSPORT_BROADCAST_ADDRESS=$BROADCAST_ADDRESS}

# SEEDS is for other nodes in the cluster we know about. If not set (because we're the only node maybe), just
# default to ourself
: ${SEEDS:="$BROADCAST_ADDRESS"}

# modify cassandra.yaml only if not linked externally
if should_auto_configure "$CASSANDRA_CONFIG" ; then
    echo "Applying changes to $CASSANDRA_CONFIG ..."

    sed -ri 's/(endpoint_snitch:).*/\1 '"$SNITCH"'/' "$CASSANDRA_CONFIG"

    # Replace the default seeds setting in cassandra.yaml
    sed -ri 's/(- seeds:).*/\1 "'"$SEEDS"'"/' "$CASSANDRA_CONFIG"

    # Update the following settings in the cassandra.yaml file based on the ENV variable values
    for name in \
        broadcast_address \
        native_transport_broadcast_address \
        cluster_name \
        listen_address \
        num_tokens \
        native_transport_address \
        start_native_transport \
        ; do
        var="${name^^}"
        val="${!var}"
        if [ "$val" ]; then
          sed -ri 's/^(# )?('"$name"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG"
        fi
    done
    echo "done."
fi

if should_auto_configure "$CASSANDRA_RACK_CONFIG" ; then
    echo "Applying changes to $CASSANDRA_RACK_CONFIG ..."
    for rackdc in dc rack; do
        var="${rackdc^^}"
        val="${!var}"
        if [ "$val" ]; then
            sed -ri 's/^('"$rackdc"'=).*/\1 '"$val"'/' "$CASSANDRA_RACK_CONFIG"
        fi
    done
    echo "done."
fi

echo "Configuring agent to connect to OpsCenter (${OPSCENTER_IP}) "
cat > "$DSE_AGENT_HOME/conf/address.yaml" <<EOF
stomp_interface: ${DSE_OPSCENTER_SERVICE_HOST}
use_ssl: 0
local_interface: ${DSE_PORT_9042_TCP_ADDR}
hosts: ["${DSE_PORT_9042_TCP_ADDR}"]
cassandra_install_location: $DSE_HOME
cassandra_log_location: /var/log/cassandra
EOF

$DSE_AGENT_HOME/bin/datastax-agent

# Run the command
echo "Running $@"
exec "$@"