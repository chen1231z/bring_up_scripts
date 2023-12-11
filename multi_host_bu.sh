#!/bin/bash
#created by : chenx.kadosh@intel.com#
#Swift SW Multi Host Bring up ( LAN + RDMA + NVMe + LCE )#

RED='\033[1;31m'
NC='\033[0m' # No Color
BOLDGREEN="\e[1;32m"
BOLDBLUE="\e[1;34m"

function rdma_workarounds()
{
# bunch of W/A needed for rdma SW driver load     
# set ARMMUSECSID=1 for RDMA in GLPE_RMI_AXI_RD_CONST and GLPE_RMI_AXI_WR_CONST1
# (to avoid C_BAD_STREAMID errors in ACC)
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'devmem 0x204200d780 32 0 &&
                                                      devmem 0x204200d77c 32 0xC0000000 &&
                                                      devmem 0x204200d778 32 0x40 &&
                                                      devmem 0x204200d774 32 0xE0000000 &&
                                                      devmem 0x204200d770 32 0x4000d &&
                                                      devmem 0x204200d76c 32 0xc0000004 &&
                                                      devmem 0x204200d620 &&
                                                      devmem 0x204200d038 32 0'
                                                      

    cpu_status=$(ssh -o StrictHostKeyChecking=no root@100.0.0.100 'devmem 0x204200d620')
    if [ $(($cpu_status)) -eq $((0x80)) ] ; 
        then echo -e ${BOLDGREEN}"RDMA W/A successfully writed"${NC}
        else exit 1
        fi
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}    
}

function nvme_workarounds()
{
# W/A for NVME cpf traffic
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}     
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'devmem 0x2026620030 32
                                                      devmem 0x202662002C 32
                                                      devmem 0x202662002C 32 24
                                                      devmem 0x202662002C 32
                                                      devmem 0x202F000034 32 0xa0000c00
                                                      devmem 0x202920C100 64 0x802
                                                      devmem 0x204b034458 w 0x10
                                                      devmem 0x204880040C w 0xA803FC00'
echo -e ${BOLDGREEN}"NVMe W/A successfully writed"${NC}                                                      
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}                                                      
}

function cp_init_changes()
{
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC} 
echo "Setting changes on cp_init.cfg file"
sleep 2   
# control plane init file changes 
# changes pf_mac_addr from the default one to "RANDOM"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'sed -i 's/00:00:00:00:03:14/RANDOM/g' /usr/bin/cplane/cp_init.cfg'   
# replaced cpf_host=0 to 4(ACC) in order to run NVME + LCE cpf on ACC      
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|cpf_host = 0|cpf_host = 4|g' /usr/bin/cplane/cp_init.cfg"
# enable T/W mode on Traffic Shaper block    
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|mode = 1|mode = 0|g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i '/\/\* For Local DDR mode, please uncomment following settings/,/\*\// { s/\/\*//; s/\*\/$//; }' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|For Local DDR mode, please uncomment following settings||g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|* 64 MB is minimum HDR size requirement||g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|* ddr_mode = 0;|ddr_mode = 0;|g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|* num_ddr_channels = 3;|num_ddr_channels = 3;|g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|* hdr_memory_size = 0x4000000;|hdr_memory_size = 0x4000000;|g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|* chunk_memory_size = 0x4000000;|chunk_memory_size = 0x4000000;|g' /usr/bin/cplane/cp_init.cfg"
# multi_host number of xeon changes 
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|num_of_xeon_hosts = 1;|num_of_xeon_hosts = 4;|g' /usr/bin/cplane/cp_init.cfg"
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 "sed -i 's|slow_ctrl_per_host = \[1, 0, 0, 0\];|slow_ctrl_per_host = \[1, 1, 1, 1\];|g' /usr/bin/cplane/cp_init.cfg"

echo -e ${BOLDGREEN}"Changes on cp_inif.cfg file confirmed"${NC}

echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}
}

function run_imccp()
{
#execute imc control plane 
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}    
    sudo printf '#!/bin/bash\ncd /usr/bin/cplane/\ncd /usr/bin/cplane\nnohup ./imccp 0000:00:01.6 0 cp_init.cfg > nop.log 2>&1 &' > /tmp/run_imccp.sh
    sudo chmod +x /tmp/run_imccp.sh
    scp -o StrictHostKeyChecking=no /tmp/run_imccp.sh  root@100.0.0.100:/home/root
    ssh -o StrictHostKeyChecking=no  root@100.0.0.100 '/home/root/run_imccp.sh'
    sleep 15
    init_done=$(ssh -o StrictHostKeyChecking=no  root@100.0.0.100 'cat /log/messages | grep "wcm sw tables initialized successfully"')
    if [ -z "$init_done" ] 
    then echo -e ${RED}"imccp falied to run"${NC}
    else echo -e ${BOLDGREEN}"imccp run successfully"${NC}
    fi
echo -e ${BOLDBLUE}"----------------------------------------------------------------------------------------------------"${NC}     
}

function acc_first_commands()
{
# Acc first commands 
    ssh -o StrictHostKeyChecking=no  root@100.0.0.100 'ssh -o StrictHostKeyChecking=no  root@192.168.96.2 " sysctl -w vm.nr_hugepages=1024 && modprobe -r nvme && 
modprobe vfio-pci enable_sriov=1 && echo 8086 1458 > /sys/bus/pci/drivers/vfio-pci/new_id && echo 8086 1457 > /sys/bus/pci/drivers/vfio-pci/new_id && echo 8086 1453 > /sys/bus/pci/drivers/vfio-pci/new_id "'
    sleep 2
}

function nvme_lce_flow()
{
#load lce driver(for MH) on ACC 
    echo -e ${BOLDBLUE}"Loading qat_lce_cpfxx on ACC (please wait) ... "${NC} 
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ssh -o StrictHostKeyChecking=no root@192.168.96.2 "modprobe qat_lce_cpfxx  apf_banks="64,64,64,64""'
    sleep 1
    cp -f /net/inx971.iil.intel.com/data/tools/Stability/Chen/sw_swift_scripts/lce_acc_commands.sh .
    scp lce_acc_commands.sh root@100.0.0.100:/home/root/
    ssh -o StrictHostKeyChecking=no  root@100.0.0.100 'scp /home/root/lce_acc_commands.sh root@192.168.96.2:/home/root/'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ssh -o StrictHostKeyChecking=no root@192.168.96.2 "/home/root/lce_acc_commands.sh"'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ssh -o StrictHostKeyChecking=no root@192.168.96.2 "dma_sample 0"'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ssh -o StrictHostKeyChecking=no root@192.168.96.2 "dc_stateless_sample_zstd"'
    echo -e ${BOLDBLUE}"please provide path to ssa_val (exmaple : /home/laduser/8929_val/ssa_val)"${NC}
    read ssa_val_path
    scp $ssa_val_path root@100.0.0.100:/home/root
    ssh -o StrictHostKeyChecking=no  root@100.0.0.100 'scp /home/root/ssa_val root@192.168.96.2:/home/root/'
    echo -e ${BOLDBLUE}"please provide path to npi_val.py (exmaple : /home/laduser/8929_val/npi_val.py)"${NC}
    read npi_val_path
    scp $npi_val_path root@100.0.0.100:/home/root
    ssh -o StrictHostKeyChecking=no  root@100.0.0.100 'scp /home/root/npi_val.py root@192.168.96.2:/home/root/'
    cp -f /net/inx971.iil.intel.com/data/tools/Stability/Chen/sw_swift_scripts/mh_nvme_acc_commands.sh .
    scp mh_nvme_acc_commands.sh  root@100.0.0.100:/home/root/
    ssh -o StrictHostKeyChecking=no  root@100.0.0.100 'scp /home/root/mh_nvme_acc_commands.sh root@192.168.96.2:/home/root/'
    ssh -o StrictHostKeyChecking=no root@100.0.0.100 'ssh -o StrictHostKeyChecking=no root@192.168.96.2 "/home/root/mh_nvme_acc_commands.sh"'
}

rdma_workarounds
nvme_workarounds
cp_init_changes
run_imccp
acc_first_commands
nvme_lce_flow






