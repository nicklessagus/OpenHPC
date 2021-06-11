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
# Esta parte del script es solamente para instalación del frontend
# - Instala un esqueleto de slurm, quizás no haga falta y se pueda hacer completo a mano despues 
# - Instala todos los paquetes de compiladores, infiniband, etcetc
# -----------------------------------------------------------------------------------------
# TODO:
# - No se si hace falta instalar muchos de esos paquetes, quizás se pueden obviar (i.e. valgrind )


inputFile=${OHPC_INPUT_LOCAL:-/opt/ohpc/pub/doc/recipes/centos8/input.local}

if [ ! -e ${inputFile} ];then
   echo "Error: Unable to access local input file -> ${inputFile}"
   exit 1
else
   . ${inputFile} || { echo "Error sourcing ${inputFile}"; exit 1; }
fi

# ---------------------------- Begin OpenHPC Recipe ---------------------------------------
# Commands below are extracted from an OpenHPC install guide recipe and are intended for 
# execution on the master SMS host.
# -----------------------------------------------------------------------------------------

# Verify OpenHPC repository has been enabled before proceeding

yum repolist | grep -q OpenHPC
if [ $? -ne 0 ];then
   echo "Error: OpenHPC repository must be enabled locally"
   exit 1
fi

# Disable firewall 
systemctl disable firewalld
systemctl stop firewalld

# ------------------------------------------------------------
# Add baseline OpenHPC and provisioning services (Section 3.3)
# ------------------------------------------------------------
yum -y install ohpc-base
yum -y install ohpc-warewulf
# Enable NTP services on SMS host
systemctl enable chronyd.service
echo "server ${ntp_server}" >> /etc/chrony.conf
echo "allow all" >> /etc/chrony.conf
systemctl restart chronyd

# -------------------------------------------------------------
# Add resource management services on master node (Section 3.4)
# -------------------------------------------------------------
yum -y install ohpc-slurm-server
cp /etc/slurm/slurm.conf.ohpc /etc/slurm/slurm.conf
perl -pi -e "s/ControlMachine=\S+/ControlMachine=${sms_name}/" /etc/slurm/slurm.conf


# Agus: Esto no se que tan bien está funcionando, a chequear con el resultado
# ----------------------------------------
# Update node configuration for slurm.conf
# ----------------------------------------
if [[ ${update_slurm_nodeconfig} -eq 1 ]];then
     perl -pi -e "s/^NodeName=.+$/#/" /etc/slurm/slurm.conf
     perl -pi -e "s/ Nodes=c\S+ / Nodes=c[1-$num_computes] /" /etc/slurm/slurm.conf
     echo -e ${slurm_node_config} >> /etc/slurm/slurm.conf
fi

# -----------------------------------------------------------------------
# Optionally add InfiniBand support services on master node (Section 3.5)
# -----------------------------------------------------------------------
if [[ ${enable_ib} -eq 1 ]];then
     yum -y groupinstall "InfiniBand Support"
     systemctl start rdma
fi

# Optionally enable opensm subnet manager
if [[ ${enable_opensm} -eq 1 ]];then
     yum -y install opensm
     systemctl enable opensm
     systemctl start opensm
fi

# Optionally enable IPoIB interface on SMS
if [[ ${enable_ipoib} -eq 1 ]];then
     # Enable ib0
     cp /opt/ohpc/pub/examples/network/centos/ifcfg-ib0 /etc/sysconfig/network-scripts
     perl -pi -e "s/master_ipoib/${sms_ipoib}/" /etc/sysconfig/network-scripts/ifcfg-ib0
     perl -pi -e "s/ipoib_netmask/${ipoib_netmask}/" /etc/sysconfig/network-scripts/ifcfg-ib0
     echo "[main]"   >  /etc/NetworkManager/conf.d/90-dns-none.conf
     echo "dns=none" >> /etc/NetworkManager/conf.d/90-dns-none.conf
     systemctl start NetworkManager
fi

# ----------------------------------------------------------------------
# Optionally add Omni-Path support services on master node (Section 3.6)
# ----------------------------------------------------------------------
if [[ ${enable_opa} -eq 1 ]];then
     yum -y install opa-basic-tools
     systemctl start rdma
fi

# Optionally enable OPA fabric manager
if [[ ${enable_opafm} -eq 1 ]];then
     yum -y install opa-fm
     systemctl enable opafm
     systemctl start opafm
fi

# -----------------------------------------------------------
# Complete basic Warewulf setup for master node (Section 3.7)
# -----------------------------------------------------------
perl -pi -e "s/device = eth1/device = ${sms_eth_internal}/" /etc/warewulf/provision.conf
ip link set dev ${sms_eth_internal} up
ip address add ${sms_ip}/${internal_netmask} broadcast + dev ${sms_eth_internal}
systemctl enable httpd.service
systemctl restart httpd
systemctl enable dhcpd.service
systemctl enable tftp.socket
systemctl start tftp.socket
if [ ! -z ${BOS_MIRROR+x} ]; then
     export YUM_MIRROR=${BOS_MIRROR}
fi


# ---------------------------------------
# Install Development Tools (Section 4.1)
# ---------------------------------------
yum -y install ohpc-autotools
yum -y install EasyBuild-ohpc
yum -y install hwloc-ohpc
yum -y install spack-ohpc
yum -y install valgrind-ohpc

# -------------------------------
# Install Compilers (Section 4.2)
# -------------------------------
yum -y install gnu9-compilers-ohpc

# --------------------------------
# Install MPI Stacks (Section 4.3)
# --------------------------------
if [[ ${enable_mpi_defaults} -eq 1 && ${enable_pmix} -eq 0 ]];then
     yum -y install openmpi4-gnu9-ohpc mpich-ofi-gnu9-ohpc
elif [[ ${enable_mpi_defaults} -eq 1 && ${enable_pmix} -eq 1 ]];then
     yum -y install openmpi4-pmix-slurm-gnu9-ohpc mpich-ofi-gnu9-ohpc
fi

if [[ ${enable_ib} -eq 1 ]];then
     yum -y install mvapich2-gnu9-ohpc
fi
if [[ ${enable_opa} -eq 1 ]];then
     yum -y install mvapich2-psm2-gnu9-ohpc
fi

# ---------------------------------------
# Install Performance Tools (Section 4.4)
# ---------------------------------------
yum -y install ohpc-gnu9-perf-tools

if [[ ${enable_geopm} -eq 1 ]];then
     yum -y install ohpc-gnu9-geopm
fi
yum -y install lmod-defaults-gnu9-openmpi4-ohpc

# ---------------------------------------------------
# Install 3rd Party Libraries and Tools (Section 4.6)
# ---------------------------------------------------
yum -y install ohpc-gnu9-serial-libs
yum -y install ohpc-gnu9-io-libs
yum -y install ohpc-gnu9-python-libs
yum -y install ohpc-gnu9-runtimes
if [[ ${enable_mpi_defaults} -eq 1 ]];then
     yum -y install ohpc-gnu9-mpich-parallel-libs
     yum -y install ohpc-gnu9-openmpi4-parallel-libs
fi
if [[ ${enable_ib} -eq 1 ]];then
     yum -y install ohpc-gnu9-mvapich2-parallel-libs
fi
if [[ ${enable_opa} -eq 1 ]];then
     yum -y install ohpc-gnu9-mvapich2-parallel-libs
fi

# -----------------------------------------------------------------------------------
# Install Optional Development Tools for use with Intel Parallel Studio (Section 4.7)
# -----------------------------------------------------------------------------------
if [[ ${enable_intel_packages} -eq 1 ]];then
     yum -y install intel-compilers-devel-ohpc
     yum -y install intel-mpi-devel-ohpc
     if [[ ${enable_opa} -eq 1 ]];then
          yum -y install mvapich2-psm2-intel-ohpc
     fi
     yum -y install ohpc-intel-serial-libs
     yum -y install ohpc-intel-geopm
     yum -y install ohpc-intel-io-libs
     yum -y install ohpc-intel-perf-tools
     yum -y install ohpc-intel-python3-libs
     yum -y install ohpc-intel-runtimes
     yum -y install ohpc-intel-mpich-parallel-libs
     yum -y install ohpc-intel-mvapich2-parallel-libs
     yum -y install ohpc-intel-openmpi4-parallel-libs
     yum -y install ohpc-intel-impi-parallel-libs
fi



















