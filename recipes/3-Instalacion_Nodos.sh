#!/bin/bash
# -----------------------------------------------------------------------------------------
#  Example Installation Script Template
#  
#  This convenience script encapsulates command-line instructions highlighted in
#  an OpenHPC Install Guide that can be used as a starting point to perform a local
#  cluster install beginning with bare-metal. Necessary inputs that describe local
#  hardware characteristics, desired network settings, and other customizations
#  are controlled via a companion input file that is used to initialize variables 
#  within this script.
#   
#  Please see the OpenHPC Install Guide(s) for more information regarding the
#  procedure. Note that the section numbering included in this script refers to
#  corresponding sections from the companion install guide.
# -----------------------------------------------------------------------------------------
# Edición Agus:
# Esta parte del script es para instalación de los nodos:
# - Directamente está comentada la parte que instala por mac y hace el wwnodescan (a lo ROCKS), quizás más adelante se le puede poner un if 
# -----------------------------------------------------------------------------------------
# TODO: 
# - No le di bola a la parte opcional del IPoIB, si se piensa usar hay que mirarla tiene la nomenclatura por default del OHPC



inputFile=${OHPC_INPUT_LOCAL:-/opt/ohpc/pub/doc/recipes/centos8/input.local}

if [ ! -e ${inputFile} ];then
   echo "Error: Unable to access local input file -> ${inputFile}"
   exit 1
else
   . ${inputFile} || { echo "Error sourcing ${inputFile}"; exit 1; }
fi


# agrega los nodos que ya se definieron
# Add hosts to cluster
echo "GATEWAYDEV=${eth_provision}" > /tmp/network.$$
wwsh -y file import /tmp/network.$$ --name network
wwsh -y file set network --path /etc/sysconfig/network --mode=0644 --uid=0


# Esto agrega los nodos ya predefinidos, por ahoro lo comento. Más adelante se puede poner un if
#for ((i=0; i<$num_computes; i++)) ; do
#   wwsh -y node new ${c_name[i]} --ipaddr=${c_ip[i]} --hwaddr=${c_mac[i]} -D ${eth_provision}
#done

# Esto es la versión que agrega mientras bootea
# la pinta de los nodos es <basename>-<rack>-<rank>

wwnodescan --netdev=${eth_provision} --ipaddr=${c_ip[0]} --netmask=${internal_netmask} --vnfs=centos8.3 --bootstrap=`uname -r` --listen=${sms_eth_internal} compute-[0-$((num_rack-1))]-[0-$((num_rank-1))]

# Add hosts to cluster (Cont.)
wwsh -y provision set "${compute_regex}" --vnfs=centos8.3 --bootstrap=`uname -r` --files=dynamic_hosts,passwd,group,shadow,munge.key,network

#esto hay que adaptarlo a la nomenclatura
#si se va a usar IPoIB hay que mirarlo
# Optionally, define IPoIB network settings (required if planning to mount Lustre over IB)
if [[ ${enable_ipoib} -eq 1 ]];then
     for ((i=0; i<$num_computes; i++)) ; do
        wwsh -y node set ${c_name[$i]} -D ib0 --ipaddr=${c_ipoib[$i]} --netmask=${ipoib_netmask}
     done
     wwsh -y provision set "${compute_regex}" --fileadd=ifcfg-ib0.ww
fi

systemctl restart dhcpd
wwsh pxe update

# Optionally, enable user namespaces
export kargs="${kargs} namespace.unpriv_enable=1"
echo "user.max_user_namespaces=15076" >> $CHROOT/etc/sysctl.conf
wwvnfs --chroot $CHROOT

# Optionally, enable console redirection
if [[ ${enable_ipmisol} -eq 1 ]];then
     wwsh -y provision set "${compute_regex}" --console=ttyS1,115200
fi

# Optionally, add arguments to bootstrap kernel
if [[ ${enable_kargs} -eq 1 ]]; then
wwsh -y provision set "${compute_regex}" --kargs="${kargs}"
fi
# ---------------------------------
# Boot compute nodes (Section 3.10)
# ---------------------------------
for ((i=0; i<${num_computes}; i++)) ; do
   ipmitool -E -I lanplus -H ${c_bmc[$i]} -U ${bmc_username} -P ${bmc_password} chassis power reset
done

# -------------------------------------------------------------
# Allow for optional sleep to wait for provisioning to complete
# -------------------------------------------------------------
sleep ${provision_wait}

# ------------------------------------
# Resource Manager Startup (Section 5)
# ------------------------------------
systemctl enable munge
systemctl enable slurmctld
systemctl start munge
systemctl start slurmctld

# TODO: No estoy seguro que funque
#pdsh -w $compute_prefix[0-1] systemctl start munge
#pdsh -w $compute_prefix[0-1] systemctl start slurmd

pdsh -w $compute_prefix[0-$((num_rack-1))]-[0-$((num_rank-1))] systemctl start munge 
pdsh -w $compute_prefix[0-$((num_rack-1))]-[0-$((num_rank-1))] systemctl start slurmd

# Optionally, generate nhc config
pdsh -w c1 "/usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c 


## acá generaba un usuario de test para probar el slurm, comento

#useradd -m test
#wwsh file resync passwd shadow group
#sleep 2
#pdsh -w $compute_prefix[0-1] /warewulf/bin/wwgetfiles 
