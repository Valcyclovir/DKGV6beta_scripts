#!/bin/bash

N1=$'\n'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\e[1m'
UNBOLD='\e[0m'

CURRENT_VERSION=6.0.0-beta.1.34
OTNODE_DIR="/root/ot-node"
GRAPHDB_FILE=$(ls /root/graphdb*.zip)
GRAPHDB_DIR=$(echo $GRAPHDB_FILE | sed 's|-dist.zip||')
BLAZEGRAPH_FILE=$(ls /root/blazegraph.jar)
BASHRC_FILE=/root/.bashrc

echo_color() {
  echo -e "$1$2$NC"
}

echo_header() {
  echo && echo_color "$YELLOW $1" && echo
}

perform_step() {
  echo -n "$2: "
  OUTPUT=$($1 2>&1)
  if [[ $? -ne 0 ]]; then
    echo_color $RED "FAILED"
    echo -e "${N1}Step failed. Output of error is:${N1}${N1}$OUTPUT"
    return 0
  else
    echo_color $GREEN "OK"
  fi
}

aliases() {
  echo "
  alias otnode-stop='systemctl stop otnode.service'
  alias otnode-start='systemctl start otnode.service'
  alias otnode-logs='journalctl -u otnode --output cat -f'
  alias otnode-config='nano ~/ot-node/.origintrail_noderc'
  " >> $BASHRC_FILE
} 

clear

cd /root

echo_header "OriginTrail v$CURRENT_VERSION update for current nodes"

if [[ -f $BASHRC_FILE ]];then
  perform_step aliases "Implementing OriginTrail aliases to .bashrc file"
  perform_step "source $BASHRC_FILE" "Sourcing bashrc file"
fi

if [[ $GRAPHDB_DIR != "" ]];then
    echo_header "Removing GraphDB and Installing Blazegraph"
    systemctl stop otnode
    IS_RUNNING=$(systemctl show -p ActiveState --value graphdb)
    if [[ $IS_RUNNING == "active" ]]; then
        perform_step "systemctl stop graphdb" "Stopping graphdb"
        perform_step "systemctl disable graphdb.service" "Disabling graphdb"
        perform_step "systemctl disable graphdb.service" "Removing graphdb service file"
        perform_step "systemctl daemon-reload" "Reloading system daemon"
    fi
fi

if [[ -f $GRAPHDB_FILE ]]; then
    rm -rf $GRAPHDB_FILE
fi

if [[ ! -f $BLAZEGRAPH_FILE ]]; then
    cd /root
    perform_step "wget https://github.com/blazegraph/database/releases/latest/download/blazegraph.jar" "Downloading Blazegraph"
    perform_step "cp /root/ot-node/installer/data/blazegraph.service /lib/systemd/system/" "Adding Blazegraph service file"
    perform_step "systemctl daemon-reload" "Reloading system daemon"
    perform_step "systemctl enable blazegraph" "Enabling Blazegraph"
    perform_step "systemctl start blazegraph" "Starting Blazegraph service"
    IMPLEMENTATION="cat $OTNODE_DIR/.origintrail_noderc | jq -r '.graphDatabase .implementation'"
    if [[ $IMPLEMENTATION != Blazegraph ]]; then
        perform_step "jq '.graphDatabase |= {"implementation": "Blazegraph", "url": "http://localhost:9999/blazegraph"} + .' $OTNODE_DIR/.origintrail_noderc >> $OTNODE_DIR/origintrail_noderc_temp"
        mv $OTNODE_DIR/origintrail_noderc_temp $OTNODE_DIR/.origintrail_noderc
    fi
    perform_step "systemctl start otnode" "Starting otnode"
fi

OUTPUT=$(curl -s --location --request GET '0.0.0.0:8900/info' | jq -r '.version')
if [[ $CURRENT_VERSION == $OUTPUT ]]; then
    echo_color $GREEN "Node successfully updated to v$CURRENT_VERSION"
else
    echo_color $RED "Node version is $OUTPUT and latest version is $CURRENT_VERSION. Please make sure your node is updated to latest version."
fi