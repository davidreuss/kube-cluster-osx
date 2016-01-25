#!/bin/bash

#  first-init.command
#

#
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source "${DIR}"/functions.sh

# get App's Resources folder
res_folder=$(cat ~/kube-cluster/.env/resouces_path)

# path to the bin folder where we store our binary files
export PATH=${HOME}/kube-cluster/bin:$PATH

echo " "
echo "Setting up Kubernetes Cluster for OS X"

# add ssh key to *.toml files
sshkey

# add ssh key to Keychain
ssh-add -K ~/.ssh/id_rsa &>/dev/null

# save user's password to Keychain
save_password
#

# Set release channel
release_channel

# create Data disk
create_data_disk

# get password for sudo
my_password=$(security find-generic-password -wa kube-cluster-app)
# reset sudo
sudo -k > /dev/null 2>&1

# Start VMs
cd ~/kube-cluster
echo " "
echo "Starting k8smaster-01 VM ..."
echo " "
echo -e "$my_password\n" | sudo -Sv > /dev/null 2>&1
#
sudo "${res_folder}"/bin/corectl load settings/k8smaster-01.toml 2>&1 | tee ~/kube-cluster/logs/first-init_master_vm_up.log
CHECK_VM_STATUS=$(cat ~/kube-cluster/logs/first-init_master_vm_up.log | grep "started")
#
if [[ "$CHECK_VM_STATUS" == "" ]]; then
    echo " "
    echo "Master VM has not booted, please check '~/kube-cluster/logs/first-init_master_vm_up.log' and report the problem !!! "
    echo " "
    pause 'Press [Enter] key to continue...'
    exit 0
else
    echo "Master VM successfully started !!!" >> ~/kube-cluster/logs/first-init_master_vm_up.log
fi
# check id /Users/homefolder is mounted, if not mount it
"${res_folder}"/bin/corectl ssh k8smaster-01 'source /etc/environment; if df -h | grep ${HOMEDIR}; then echo 0; else sudo systemctl restart ${HOMEDIR}; fi' > /dev/null 2>&1
# save master VM's IP
"${res_folder}"/bin/corectl q -i k8smaster-01 | tr -d "\n" > ~/kube-cluster/.env/master_ip_address
# get master VM's IP
master_vm_ip=$("${res_folder}"/bin/corectl q -i k8smaster-01)
# update nodes cloud-init file with master's IP
sed -i "" "s/_MASTER_IP_/$master_vm_ip/" ~/kube-cluster/cloud-init/user-data.node
#
echo " "
echo "Starting k8snode-01 VM ..."
echo -e "$my_password\n" | sudo -Sv > /dev/null 2>&1
#
sudo "${res_folder}"/bin/corectl load settings/k8snode-01.toml 2>&1 | tee ~/kube-cluster/logs/first-init_node1_vm_up.log
CHECK_VM_STATUS=$(cat ~/kube-cluster/logs/first-init_node1_vm_up.log | grep "started")
#
if [[ "$CHECK_VM_STATUS" == "" ]]; then
    echo " "
    echo "Node1 VM has not booted, please check '~/kube-cluster/logs/first-init_node1_vm_up.log' and report the problem !!! "
    echo " "
    pause 'Press [Enter] key to continue...'
    exit 0
else
    echo "Node1 VM successfully started !!!" >> ~/kube-cluster/logs/first-init_node1_vm_up.log
fi
# check id /Users/homefolder is mounted, if not mount it
"${res_folder}"/bin/corectl ssh k8snode-01 'source /etc/environment; if df -h | grep ${HOMEDIR}; then echo 0; else sudo systemctl restart ${HOMEDIR}; fi' > /dev/null 2>&1
echo " "
# save node1 VM's IP
"${res_folder}"/bin/corectl q -i k8snode-01 | tr -d "\n" > ~/kube-cluster/.env/node1_ip_address
# get node1 VM's IP
node1_vm_ip=$("${res_folder}"/bin/corectl q -i k8snode-01)
#
#
echo " "
echo "Starting k8snode-02 VM ..."
echo -e "$my_password\n" | sudo -Sv > /dev/null 2>&1
#
sudo "${res_folder}"/bin/corectl load settings/k8snode-02.toml 2>&1 | tee ~/kube-cluster/logs/first-init_node2_vm_up.log
CHECK_VM_STATUS=$(cat ~/kube-cluster/logs/first-init_node2_vm_up.log | grep "started")
#
if [[ "$CHECK_VM_STATUS" == "" ]]; then
    echo " "
    echo "Node2 VM has not booted, please check '~/kube-cluster/logs/first-init_node2_vm_up.log' and report the problem !!! "
    echo " "
    pause 'Press [Enter] key to continue...'
    exit 0
else
    echo "Node2 VM successfully started !!!" >> ~/kube-cluster/logs/first-init_node2_vm_up.log
fi
# check id /Users/homefolder is mounted, if not mount it
"${res_folder}"/bin/corectl ssh k8snode-02 'source /etc/environment; if df -h | grep ${HOMEDIR}; then echo 0; else sudo systemctl restart ${HOMEDIR}; fi' > /dev/null 2>&1
echo " "
# save node2 VM's IP
"${res_folder}"/bin/corectl q -i k8snode-02 | tr -d "\n" > ~/kube-cluster/.env/node2_ip_address
# get node2 VM's IP
node2_vm_ip=$("${res_folder}"/bin/corectl q -i k8snode-02)
###

# install k8s files on to VMs
install_k8s_files
#

# download latest version of fleetctl and helm clients
download_osx_clients
#

# run helm for the first time
helm up
# add kube-charts repo
helm repo add kube-charts https://github.com/TheNewNormal/kube-charts
# Get the latest version of all Charts from repos
helm up

# set etcd endpoint
export ETCDCTL_PEERS=http://$master_vm_ip:2379

# set fleetctl endpoint and install fleet units
export FLEETCTL_TUNNEL=
export FLEETCTL_ENDPOINT=http://$master_vm_ip:2379
export FLEETCTL_DRIVER=etcd
export FLEETCTL_STRICT_HOST_KEY_CHECKING=false
echo " "
echo "fleetctl list-machines:"
fleetctl list-machines
echo " "
#
deploy_fleet_units
#

sleep 2

# generate kubeconfig file
echo Generate kubeconfig file ...
"${res_folder}"/bin/gen_kubeconfig $master_vm_ip
#

# set kubernetes master
export KUBERNETES_MASTER=http://$master_vm_ip:8080
#
echo Waiting for Kubernetes cluster to be ready. This can take a few minutes...
spin='-\|/'
i=1
until curl -o /dev/null http://$master_vm_ip:8080 >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
i=1
until ~/kube-cluster/bin/kubectl version | grep 'Server Version' >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\b${spin:i++%${#sp}:1}"; sleep .1; done
i=1
until ~/kube-cluster/bin/kubectl get nodes | grep $master_vm_ip >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
echo " "
# attach label to the node
~/kube-cluster/bin/kubectl label nodes $master_vm_ip node=worker1
#
install_k8s_add_ons "$master_vm_ip"
#
echo "fleetctl list-machines:"
fleetctl list-machines
echo " "
echo "fleetctl list-units:"
fleetctl list-units
echo " "
echo "kubectl get nodes:"
~/kube-cluster/bin/kubectl get nodes
echo " "
#
echo "Installation has finished, Kube Cluster VMs are up and running !!!"
echo " "
echo "Assigned static IP for master VM: $master_vm_ip"
echo "Assigned static IP for node1 VM: $node1_vm_ip"
echo "Assigned static IP for node2 VM: $node2_vm_ip"
echo " "
echo "You can control this App via status bar icon... "
echo " "

echo "Also you can install Deis PaaS (http://deis.io) v2 alpha version with 'install_deis' command ..."
echo " "

cd ~/kube-cluster
# open bash shell
/bin/bash




