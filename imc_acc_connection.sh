#!/bin/bash
#created by : chenx.kadosh@intel.com#
#Enable IMC+ACC Connection#

RED='\033[1;31m'
NC='\033[0m' # No Color
BOLDGREEN="\e[1;32m"
BOLDBLUE="\e[1;34m"


function set_imc_acc_connection() {
    # remove .ssh/known_hosts file
    sudo rm -rf .ssh/known_hosts
    sudo rm -rf /root/.ssh/known_hosts

    # get the list of interfaces (excluding eth0)
    interfaces=$(ifconfig -a | grep -oE '^[A-Za-z0-9]+' | grep -v '^eth0$')
    echo -e ${BOLDBLUE}"List of interfaces connected to the host"${NC}
    echo -e ${BOLDBLUE}"$interfaces"${NC}
    sleep 2

    # iterate through the interfaces and check if they have a carrier
    found_interface=false
    for interface in $interfaces; do
        if [ -e "/sys/class/net/$interface/carrier" ]; then
            link_status=$(cat "/sys/class/net/$interface/carrier")
            if [ "$link_status" -eq 1 ]; then
                sudo ip addr add 100.0.0.1/24 brd + dev "$interface"
                echo -e ${BOLDGREEN}"$interface is connected to MEV"${NC}
                found_interface=true
                break
            fi
        fi
    done

    # if no suitable interface is found, print a message and exit
    if [ "$found_interface" == false ]; then
        echo -e ${RED}"No suitable interface found. Connect USB2LAN from Springville to host"${NC}
        exit 1
    fi

    # check connection to IMC
    check_imc=$(ping -c 2 100.0.0.100 | grep 0% | awk '{print $6}')
    if [ "$check_imc" == 0% ]; then
        echo -e ${BOLDGREEN}"Connection to IMC established"${NC}
    else
        echo -e ${RED}"Check connection to IMC "${NC}
        exit 1
    fi

    # create imc<-->acc connection
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'modprobe icc_net'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ip link set eth2 up'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ip link set lo up'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ip a a 192.168.96.1/24 brd + dev eth2'

    # verify acc connection worked
    connection_established=$(ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ssh -o StrictHostKeyChecking=no root@192.168.96.2 "whoami" ')
    if [ "$connection_established" == root ]; then
        echo -e ${BOLDGREEN}"ACC connection succeeded"${NC}
    else
        echo -e ${RED}"Check connection to ACC"${NC}
    fi
}

set_imc_acc_connection
