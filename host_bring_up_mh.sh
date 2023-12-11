#!/bin/bash
#created by : chenx.kadosh@intel.com#
#Mh bring up hosts ( LAN + RDMA + NVMe + LCE )#

RED='\033[1;31m'
NC='\033[0m' # No Color
BOLDGREEN="\e[1;32m"
BOLDBLUE="\e[1;34m"


function load_nvme_driver()
{
# Loading NVMe driver on host 0 (single-host)
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
    echo -e ${BOLDBLUE}"Executing NVME (spdk_perf app on host)"${NC}
    echo "Creating NVME bdf"
    sudo sysctl -w vm.nr_hugepages=1024
    sudo modprobe vfio-pci enable_sriov=1
    echo 8086 1457 | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id
    pf_bdf="$(lspci -n | grep 8086:1457 | sed -n "s/ .*//p")"

# Executing spdk_nvme_perf app
    sudo -E spdk_nvme_perf -r "trtype:PCIe traddr:$pf_bdf" -T nvme --io-depth 128 --io-size 4096 --io-pattern read -t 5    
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
}

function load_lce_driver()
{
# Loading and executing LCE commands on host 0 (single-host)
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
    echo -e ${BOLDBLUE}"Executing LCE apf on host"${NC}
    sudo rmmod qat_lce_apfxx
    sudo modprobe qat_lce_apfxx
    sudo dma_sample 0
    sudo dc_stateless_sample_zstd 
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}           
}

function load_idpf_driver()
{
# loading idpf commercial driver
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
    echo -e ${BOLDBLUE}"Loading idpf + rdma commercial driver"${NC}
    echo -e 
    sudo modprobe idpf
    sleep 3
    idpf=$(lsmod | grep idpf | awk NR==1 | awk '{print $1}')
    if [ $idpf == idpf ]
    then 
        echo -e ${BOLDGREEN}"idpf driver loaded successfully"${NC} 
    else
        echo -e ${RED}"driver was not loaded"${NC}
    fi
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
}

load_nvme_driver
load_lce_driver
load_idpf_driver
