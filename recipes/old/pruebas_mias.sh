### acá hay un script para sacar data
# https://github.com/Microway/MCMS-OpenHPC-Recipe/blob/master/install_head_node.sh


sudo su

export SMS_NAME=frontend
export SMS_IP=10.0.0.1
export SMS_ETH_INTERNAL=enp0s8
#export INTERNAL_NETMASK=255.255.255.0
export NAGIOS_WEB_PASSWORD=123
export COMPUTE_PREFIX=compute-
export NUM_COMPUTES=4
export CHROOT=/opt/ohpc/admin/images/centos8.3
export COMPUTE_REGEX=compute-0-*
export ETH_PROVISION=eth0


##Por si no tiene el pxe configurado
#ipmitool -E -I lanplus -H ${bmc_ipaddr} -U root chassis bootdev pxe options=persistent

#locales del orto
dnf install langpacks-en glibc-all-langpacks -y
systemctl disable firewalld
systemctl stop firewalld

#creo que sino no instala algun componente del openhpc
#yum install dnf-plugins-core
dnf config-manager --set-enabled powertools
yum -y install http://repos.openhpc.community/OpenHPC/2/CentOS_8/x86_64/ohpc-release-2-1.el8.x86_64.rpm

yum -y install ohpc-base
yum -y install ohpc-warewulf
yum -y install ohpc-slurm-server

#NTP, puse uno de acá
systemctl enable chronyd.service
echo "server 162.159.200.1" >> /etc/chrony.conf
echo "allow all" >> /etc/chrony.conf
systemctl restart chronyd

#############estado salvado

###SLURM
# Use ohpc-provided file for starting SLURM configuration
cp /etc/slurm/slurm.conf.ohpc /etc/slurm/slurm.conf

# Identify resource manager hostname on master host
perl -pi -e "s/ControlMachine=\S+/ControlMachine=frontend/" /etc/slurm/slurm.conf

##Agregar soporte infiniband en el frontend

#yum -y groupinstall "InfiniBand Support"
## Load IB drivers
#systemctl start rdma
#Hay más cosas infiniband (ipoIB) pero lo salteo para probar acá


#setting up Warewulf
# Configure Warewulf provisioning to use desired internal interface
# configuré la ip interna en 10.0.0.1

perl -pi -e "s/device = eth1/device = ${SMS_ETH_INTERNAL}/" /etc/warewulf/provision.conf

# esto creo que lo hice a mano en el frontend, comento
#ip link set dev ${SMS_ETH_INTERNAL} up
#ip address add ${SMS_IP}/${INTERNAL_NETMASK} broadcast + dev ${sms_eth_internal}
#ifconfig ${SMS_ETH_INTERNAL} ${SMS_IP} netmask ${INTERNAL_NETMASK} up

# Restart/enable relevant services to support provisioning

systemctl enable httpd.service
systemctl restart httpd
systemctl enable dhcpd.service
systemctl enable tftp.socket
systemctl start tftp.socket

## Definir la imagen para los nodos
## (presupone que se puede acceder hacia afuera)

# Define chroot location
export CHROOT=/opt/ohpc/admin/images/centos8.3

# Build initial chroot image
wwmkchroot -v centos-8 $CHROOT

# Enable OpenHPC and EPEL repos inside chroot
dnf -y --installroot $CHROOT install epel-release
cp -p /etc/yum.repos.d/OpenHPC*.repo $CHROOT/etc/yum.repos.d

##############################
## Agrega componentes OpenHPC a la imagen

# Install compute node base meta-package
yum -y --installroot=$CHROOT install ohpc-base-compute

## Para habilitar dns 
cp -p /etc/resolv.conf $CHROOT/etc/resolv.conf

##############################
## Componentes adicionales

# copy credential files into $CHROOT to ensure consistent uid/gids for slurm/munge at
# install. Note that these will be synchronized with future updates via the provisioning system.


## NOTA poner yes
cp /etc/passwd /etc/group $CHROOT/etc


# Add Slurm client support meta-package and enable munge

yum -y --installroot=$CHROOT install ohpc-slurm-client
chroot $CHROOT systemctl enable munge

# Register Slurm server with computes (using "configless" option)
echo SLURMD_OPTIONS="--conf-server ${SMS_IP}" > $CHROOT/etc/sysconfig/slurmd

# Add Network Time Protocol (NTP) support
yum -y --installroot=$CHROOT install chrony
# Identify master host as local NTP server
echo "server ${SMS_IP}" >> $CHROOT/etc/chrony.conf

# Add kernel drivers (matching kernel version on SMS node)
## yum -y --installroot=$CHROOT install kernel-`uname -r`
# no me funcó, tuve que mandar: 

yum -y --installroot=$CHROOT install kernel.x86_64

# Include modules user environment
yum -y --installroot=$CHROOT install lmod-ohpc

################ OTRA IMAGEN SALVADA ANTES DE LUCHAR CON LA BASE
# Configuración de sistema, agrega claves para el nfs y eso

# Initialize warewulf database and ssh_keys
wwinit database
wwinit ssh_keys

# Add NFS client mounts of /home and /opt/ohpc/pub to base image

echo "${SMS_IP}:/home /home nfs nfsvers=3,nodev,nosuid 0 0" >> $CHROOT/etc/fstab
echo "${SMS_IP}:/opt/ohpc/pub /opt/ohpc/pub nfs nfsvers=3,nodev 0 0" >> $CHROOT/etc/fstab

################ NAGIOS  #######
## Se puede agregar configuración opcional ahora
## Agrego nagios y clustershell (tambien se puede poner lo de que se pueda acceder a máquinas en las que se tenga trabajos corriendo)

# Install nagios, nrep, and all available plugins on master host
yum -y install --skip-broken nagios nrpe nagios-plugins-*

# Install nrpe and an example plugin into compute node image
yum -y --installroot=$CHROOT install nrpe nagios-plugins-ssh


# Enable and configure Nagios NRPE daemon in compute image

chroot $CHROOT systemctl enable nrpe
perl -pi -e "s/^allowed_hosts=/# allowed_hosts=/" $CHROOT/etc/nagios/nrpe.cfg
echo "nrpe : ${sms_ip} : ALLOW" >> $CHROOT/etc/hosts.allow
echo "nrpe : ALL : DENY" >> $CHROOT/etc/hosts.allow


# Copy example Nagios config file to define a compute group and ssh check
# (note: edit as desired to add all desired compute hosts)

cp /opt/ohpc/pub/examples/nagios/compute.cfg /etc/nagios/objects
# Register the config file with nagios
echo "cfg_file=/etc/nagios/objects/compute.cfg" >> /etc/nagios/nagios.cfg

# Update location of mail binary for alert commands
perl -pi -e "s/ \/bin\/mail/ \/usr\/bin\/mailx/g" /etc/nagios/objects/commands.cfg

# Update email address of contact for alerts
# export sms_name=frontend
perl -pi -e "s/nagios\@localhost/root\@${SMS_NAME}/" /etc/nagios/objects/contacts.cfg

# Add check_ssh command for remote hosts

echo command[check_ssh]=/usr/lib64/nagios/plugins/check_ssh localhost $CHROOT/etc/nagios/nrpe.cfg

# define password for nagiosadmin to be able to connect to web interface
# export nagios_web_password=123
htpasswd -bc /etc/nagios/passwd nagiosadmin ${NAGIOS_WEB_PASSWORD}

# Enable Nagios on master, and configure
systemctl enable nagios
systemctl start nagios

# Update permissions on ping command to allow nagios user to execute

chmod u+s `which ping`

###################  CLUSTERSHELL

## A REVISAR
# Setup node definitions


cd /etc/clustershell/groups.d
mv local.cfg local.cfg.orig
echo "adm: ${SMS_NAME}" > local.cfg
echo "compute: ${COMPUTE_PREFIX}[1-${NUM_COMPUTES}]" >> local.cfg
echo "all: @adm,@compute" >> local.cfg

#### Para distribuir credenciales entre los nodos

wwsh file import /etc/passwd
wwsh file import /etc/group
wwsh file import /etc/shadow
wwsh file import /etc/munge/munge.key

# para controlar IPoIP
wwsh file import /opt/ohpc/pub/examples/network/centos/ifcfg-ib0.ww
wwsh -y file set ifcfg-ib0.ww --path=/etc/sysconfig/network-scripts/ifcfg-ib0

#####Armando la imagen bootstrap (kernel y módulos)
export WW_CONF=/etc/warewulf/bootstrap.conf
echo "drivers += updates/kernel/" >> $WW_CONF

# Build bootstrap image
wwbootstrap `uname -r`

########## Virtual node filesystem
## With the local site customizations in place, the following step uses the wwvnfs command to assemble a VNFS capsule from the chroot environment defined for the compute instance.

wwvnfs --chroot $CHROOT
#opcion de intel
#wwvnfs --chroot $CHROOT --hybridize


#### snapshot por lo de las provisiones

# Set provisioning interface as the default networking device
#SERÁ ESTA?
export ETH_PROVISION=eth0

echo "GATEWAYDEV=${ETH_PROVISION}" > /tmp/network.$$
wwsh -y file import /tmp/network.$$ --name network
wwsh -y file set network --path /etc/sysconfig/network --mode=0644 --uid=0

## hay varias cosas de mellanox e IB


# usando nodescan para agregar los nodos automaticamenta a la base
#puse tres para probar
wwnodescan --netdev=eth0 --ipaddr=10.0.0.2 --netmask=255.255.255.0 --vnfs=centos8.3 --bootstrap=`uname -r` --listen=${SMS_ETH_INTERNAL} compute-0-[0-3]

#provision interface for computer
## ${compute_regex} Compute Node Name Regex Matching cn[01-04]

export COMPUTE_REGEX=compute-0-*

# los nodos bootean, cargan la imagen y arrancan
wwsh -y provision set "${COMPUTE_REGEX}" --vnfs=centos8.3 --bootstrap=`uname -r` \ --files=dynamic_hosts,passwd,group,shadow,munge.key,network

# Restart dhcp / update PXE

wwsh dhcp restart
wwsh pxe update

#acordarse que tambien probé editar /etc/warewulf/defaults/provision.conf 

##########
## bueno, ahora tenemos nodos que bootean pero no se están levando las claves ni el munge, paso a paso

## Statefull provisioning

# Add GRUB2 bootloader and re-assemble VNFS image
yum -y --installroot=$CHROOT install grub2
wwvnfs --chroot $CHROOT

# Select (and customize) appropriate parted layout example
cp /etc/warewulf/filesystem/examples/gpt_example.cmds /etc/warewulf/filesystem/gpt.cmds
wwsh provision set --filesystem=gpt "${COMPUTE_REGEX}"
wwsh provision set --bootloader=sda "${COMPUTE_REGEX}"

# prueba
#wwsh -y provision set "${COMPUTE_REGEX}" --vnfs=centos8.3 --bootstrap=`uname -r` \ --files=dynamic_hosts,passwd,group,shadow,munge.key,network --filesystem=gpt --bootloader=sda


## ahora viene lode uefi
# Add GRUB2 bootloader and re-assemble VNFS image
#yum -y --installroot=$CHROOT install grub2-efi grub2-efi-modules
#wwvnfs --chroot $CHROOT
#cp /etc/warewulf/filesystem/examples/efi_example.cmds /etc/warewulf/filesystem/efi.cmds
#wwsh provision set --filesystem=efi "${COMPUTE_REGEX}"
#wwsh provision set --bootloader=sda "${COMPUTE_REGEX}"

# Configure local boot (after successful provisioning)
wwsh provision set --bootlocal=normal "${COMPUTE_REGEX}"


############## PROBANDO


################################################################################
# Install Development Tools
################################################################################

yum -y install ohpc-autotools
yum -y install valgrind-ohpc
yum -y install EasyBuild-ohpc
yum -y install spack-ohpc
yum -y install gnu9-compilers-ohpc
yum -y install openmpi4-gnu9-ohpc mpich-ofi-gnu9-ohpc
yum -y install mpich-ucx-gnu9-ohpc
yum -y install ohpc-gnu9-mpich-parallel-libs

# Install perf-tools meta-package
yum -y install ohpc-gnu9-perf-tools
#The following package install provides a default environment that enables autotools,the GNU compiler toolchain, and the OpenMPI stack.
yum -y install lmod-defaults-gnu9-openmpi4-ohpc

# SLURM

# Start munge and slurm controller on master host
systemctl enable munge
systemctl enable slurmctld
systemctl start munge
systemctl start slurmctld

# Start slurm clients on compute hosts
pdsh -w compute-0-[0-3] systemctl start munge
pdsh -w compute-0-[0-3] systemctl start slurmd

# Generate NHC configuration file based on compute node environment
# a chequear la linea
pdsh -w compute-0-[0-3] "/usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c

# Run test job
useradd -m test
wwsh file resync passwd shadow group

#para forzar la sincronización
pdsh -w compute-0-[0-3]  /warewulf/bin/wwgetfiles

#correr test
su - test
# Compile MPI "hello world" example
mpicc -O3 /opt/ohpc/pub/examples/mpi/hello.c

# Submit interactive job request and use prun to launch executable
srun -n 8 -N 2 --pty /bin/bash
prun ./a.out

[prun] Master compute host = c1
[prun] Resource manager = slurm
[prun] Launch cmd = mpiexec.hydra -bootstrap slurm ./a.out

