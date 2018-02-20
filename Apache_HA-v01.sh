#! /bin/bash
## Script Apache-JBCS HA  v1.0
## Edit 13 Feb 2018
## By Supattra@DCS

source /etc/profile

##################################
##	VRA PASS PARAMETER	##
##################################

PROJCODE="LMS"
if [ -z ${PROJCODE} ]
then
    exit 99;
fi

APP01_IP="192.168.134.156"
APP02_IP="192.168.134.157"
WEB01_IP="192.168.134.158"
WEB02_IP="192.168.134.159"
#DBSIP="192.168.134.161"


APPSNET="255.255.255.0"
WEBSNET="255.255.255.0"
DBSSNET="255.255.255.0"

APP01_HOST="app01"
APP02_HOST="app02"
WEB01_HOST="web01"
WEB02_HOST="web02"
#DBSHOST="db01"


##########################################
##	EDIT VARIABLE BY SOFTWARE	##
##########################################
PROJCODE="$(echo $PROJCODE | tr '[:upper:]' '[:lower:]')"
#REPO_IP=192.168.134.136
REPO_IP=172.31.226.165
DISKSW=/dev/sdc

NETDEV1="eth0"
NETDEV2="eth1"

WEBUSR="acusr"
WEBUID="2000"
WEBGRP="acgrp"
WEBGID="2000"

APPUSR="jbusr"
APPUID="2001"
APPGRP="jbgrp"
APPGID="2001"

##################################
##	CONFIG HOSTS FILES	##
##################################

function addHost(){
    IPSERV=$1
    HOSTNAME=$2

    HOSTLISTS=`grep "${IPSERV}" /etc/hosts`
    echo "$1,$2"

    if [ -z "${HOSTLISTS}" ]
    then
        echo "${IPSERV}     ${HOSTNAME}" >> /etc/hosts
    else
        if [ $(echo ${HOSTLISTS[@]} | grep -o " ${HOSTNAME}" | wc -w) == 0 ]
        then
        sed -i -e "/${IPSERV}/ s/$/ $HOSTNAME/" /etc/hosts
        fi
    fi
}


HOSTNAME=`hostname`
IPSERV=`ip -o -f inet addr show ${NETDEV1}| awk '/scope global/ {print $4}' | awk -F"/" '{print $1}'`
addHost "${IPSERV}" "${HOSTNAME}"

HOSTMNT="${HOSTNAME}"_mnt
IPMNT=`ip -o -f inet addr show ${NETDEV2}| awk '/scope global/ {print $4}' | awk -F"/" '{print $1}'`
addHost "${IPMNT}" "${HOSTMNT}"


##################################
### config hosts file for APP  ###
##################################
if [ ${APP01_IP} ]; then
   APP01_ALIAS="jboss"${PROJCODE}"srv01"
   addHost "${APP01_IP}" "${APP01_HOST}"
   addHost "${APP01_IP}" "${APP01_ALIAS}"
fi

if [ ${APP02_IP} ]; then
   APP02_ALIAS="jboss"${PROJCODE}"srv02"
   addHost "${APP02_IP}" "${APP02_HOST}"
   addHost "${APP02_IP}" "${APP02_ALIAS}"
fi

if [ ${WEB01_IP} ]; then
   WEB01_ALIAS="jboss"${PROJCODE}"web01"
   addHost "${WEB01_IP}" "${WEB01_HOST}"
   addHost "${WEB01_IP}" "${WEB01_ALIAS}"
fi

if [ ${WEB02_IP} ]; then
   WEB02_ALIAS="jboss"${PROJCODE}"web02"
   addHost "${WEB02_IP}" "${WEB02_HOST}"
   addHost "${WEB02_IP}" "${WEB02_ALIAS}"
fi

if [ ${DBSIP} ]; then
   DB01_ALIAS=${PROJCODE}"db01"
   addHost "${DBSIP}" "${DBSHOST}"
   addHost "${DBSIP}" "${DB01_ALIAS}"
fi


##########################################
##	CHECK PRIMARY/SECONDARY NODE	##
##########################################

IPNET01=`ifconfig ${NETDEV1}| grep "inet " | awk '{print $2}'`

if [ "${IPNET01}" == "${WEB01_IP}" ];then
   echo "This primary node (Web connect to master Controller host)"
   WEBNODE=1
elif [ "${IPNET01}" == "${WEB02_IP}" ];then
   echo "This secondary node (Web connect to slave controller host)"
   WEBNODE=2
else
   echo "Error for check this server is primary node/secondary node"
   exit 99;
fi


##############################
##	ADD USER/GROUP	    ##
##############################
echo "groupadd --gid ${WEBGID} ${WEBGRP}"
groupadd --gid ${WEBGID} ${WEBGRP}
echo "groupadd --gid ${APPGID} ${APPGRP}"
groupadd --gid ${APPGID} ${APPGRP}
useradd --gid ${WEBGID} -G ${WEBGID},${APPGID} --uid ${WEBUID} ${WEBUSR} 
useradd --gid ${APPGID} -G ${APPGID},${WEBGID} --uid ${APPUID} ${APPUSR} 


##################################################
##	CREATE FS LAYOUT FOR APACHE-JBCS	##
##################################################

if [ ${DISKWEB} ]; then
  DISKSW="${DISKWEB}"
fi

echo "$DISKSW"

SIZE=40GB
VGNAME=appjbvg
LVM_NAME=("apachebin" "apachelog" "apachedump")
LVM_SIZE=("9G" "20G" "10G")
FS_PATH=("/apache" "/apache_log" "/apache_dump")


pvcreate $DISKSW
vgcreate $VGNAME $DISKSW 

i=0
for Path in "${FS_PATH[@]}"; do
 echo "lvcreate -L ${LVM_SIZE[$i]} -n ${LVM_NAME[$i]} $VGNAME"
 lvcreate -L ${LVM_SIZE[$i]} -n ${LVM_NAME[$i]} $VGNAME
 echo "mkfs.ext4 /dev/$VGNAME/${LVM_NAME[$i]}"
 mkfs.ext4 /dev/$VGNAME/${LVM_NAME[$i]}
 echo "mkdir -p ${FS_PATH[$i]}"
 mkdir -p ${FS_PATH[$i]}
 echo "/dev/mapper/$VGNAME-${LVM_NAME[$i]}     ${FS_PATH[$i]}    ext4    defaults   0 0" 
 echo "/dev/mapper/$VGNAME-${LVM_NAME[$i]}     ${FS_PATH[$i]}    ext4    defaults   0 0"  >> /etc/fstab
 echo "mount ${FS_PATH[$i]}"
 mount ${FS_PATH[$i]}
 chown -R ${WEBUSR}:${WEBGRP}  ${FS_PATH[$i]}
 chmod -R 775 ${FS_PATH[$i]}
 let i=i+1
done


#################################
##	INSTALL SOFTWARE       ##  
#################################


#### Get JBoss Core Service Repository in /etc/yum.repo.d ####
echo "1.0 === Get JBOSS Repository to /etc/yum.repo.d ==="
echo "wget --no-check-certificate https://$REPO_IP/jboss/jboss.repo -P /etc/yum.repos.d/"
wget --no-check-certificate https://$REPO_IP/jboss/jboss.repo -P /etc/yum.repos.d/
echo "wget --no-check-certificate https://$REPO_IP/oraclejava/oraclejava.repo -P /etc/yum.repos.d/"
wget --no-check-certificate https://$REPO_IP/oraclejava/oraclejava.repo -P /etc/yum.repos.d/

#### Install JBoss Core Service pkg ####
echo "2.0 === Install JBoss Core Service ==="
echo "yum groupinstall -y jbcs-httpd24"
yum groupinstall -y jbcs-httpd24
echo "yum install -y jdk1.8.x86_64"
yum install -y jdk1.8.x86_64 

if [ ${WEBNODE} == 2 ] 
then
     WEBIP=${WEB02_IP} 
     WEBHOST=${WEB02_HOST}
     APPIP=${APP02_IP} 
else 
     WEBIP=${WEB01_IP}
     WEBHOST=${WEB01_HOST}
     APPIP=${APP01_IP}
fi

#SOL_NAME="lms"
SUBNET_SERVICE="${WEBIP}/${WEBSNET}"
if [ ${APPIP} ]
then 
SUBNET_APP="${APPIP}/${APPSNET}"
else
SUBNET_APP="127.0.0.1"
fi

#### Config Apache JBOSS  ####

#read -p "Enter SOL Name : " SOL_NAME
#read -p "Enter Appliaction Subnet : " SUBNET_APP 
#read -p "Enter Web Server Subnet  : " SUBNET_SERVICE


#SERVER_NAME="apache${SOL_NAME}01:443"
SERVER_NAME="${WEBHOST}:443"
HTTPD_PATH="/opt/rh/jbcs-httpd24"

WEBALIAS="jboss"${PROJCODE}"web0"${WEBNODE}

cp -arx ${HTTPD_PATH}/root/etc/httpd/conf/httpd.conf ${HTTPD_PATH}/root/etc/httpd/conf/httpd.conf.backup

sed -i -e '/^ErrorLog /s/ .*/ \/apache_log\/error_log/'  ${HTTPD_PATH}/root/etc/httpd/conf/httpd.conf
sed -i -e '/^CustomLog /s/ .*/ \/apache_log\/access_log combined/'  ${HTTPD_PATH}/root/etc/httpd/conf/httpd.conf 
sed -i -e '/^User /s/ .*/ acusr/'  ${HTTPD_PATH}/root/etc/httpd/conf/httpd.conf 
sed -i -e '/^Group /s/ .*/ acgrp/'  ${HTTPD_PATH}/root/etc/httpd/conf/httpd.conf 

cp -arx ${HTTPD_PATH}/root/etc/httpd/conf.d/ssl.conf ${HTTPD_PATH}/root/etc/httpd/conf.d/ssl.conf.backup
mkdir -p $HTTPD_PATH/keys
### GET KEY FILE ###

wget --no-check-certificate https://$REPO_IP/jboss/addons/certweb.tar -P /tmp
tar -C ${HTTPD_PATH}/keys -xvf /tmp/certweb.tar

echo "sed  -e '/SSLCACertificateFile/ a SSLCACertificatePath $HTTPD_PATH\/keys\/trust\/\n'  -e '/<\/Location>/ a <Location /mod_cluster-manager>\n    SetHandler mod_cluster-manager\n    Allow from All \n<\/Location>' -e '/<\/Directory>/ a <Directory />\n    Require ip $SUBNET_SERVICE\n<\/Directory>' -e '/#ServerName/ a ServerName ${SERVER_NAME}' $HTTPD_PATH/root/etc/httpd/conf.d/ssl.conf.backup > ${HTTPD_PATH}/root/etc/httpd/conf.d/ssl.conf" > cmd.sh;
chmod 755 cmd.sh;./cmd.sh;rm -f cmd.sh;


`sed -i -e '/^Listen / s/ .*/ 443 /' ${HTTPD_PATH}/root/etc/httpd/conf.d/ssl.conf`
`sed -i -e '/^SSLCertificateFile / s/ .*/ \/opt\/rh\/jbcs-httpd24\/keys\/key.cer /' ${HTTPD_PATH}/root/etc/httpd/conf.d/ssl.conf`
`sed -i -e '/^SSLCertificateKeyFile / s/ .*/ \/opt\/rh\/jbcs-httpd24\/keys\/key.key /' ${HTTPD_PATH}/root/etc/httpd/conf.d/ssl.conf` 

MODCS_PATH="/opt/rh/jbcs-httpd24/root/etc/httpd/conf.d/mod_cluster.conf"
cp -arx ${MODCS_PATH} ${MODCS_PATH}.backup

SUBNET_SERVICE=${SUBNET_SERVICE//\//\\/}
SUBNET_APP=${SUBNET_APP//\//\\/}


echo "WEBALIAS = ${WEBALIAS}"

echo "sed -e '/<Location \/mod_cluster_manager>/,/^</ s/Require ip 127.0.0.1/Require ip ${SUBNET_SERVICE}/'  -e '/<Directory \/>/,/^</ s/Require ip 127.0.0.1/Require ip ${SUBNET_APP}/' ${MODCS_PATH}.backup > ${MODCS_PATH}" > cmd.sh;
chmod 755 cmd.sh;./cmd.sh; rm -f cmd.sh;

echo "sed -i -e \"/^.*Listen /s/ .*/ Listen  ${WEBALIAS}:6666/\" /opt/rh/jbcs-httpd24/root/etc/httpd/conf.d/mod_cluster.conf"
`sed -i -e "/^.*Listen /s/ .*/ Listen  ${WEBALIAS}:6666/" /opt/rh/jbcs-httpd24/root/etc/httpd/conf.d/mod_cluster.conf`

echo "sed -i -e \"/^.*<VirtualHost /s/ .*/  <VirtualHost  ${WEBALIAS}:6666>/\" /opt/rh/jbcs-httpd24/root/etc/httpd/conf.d/mod_cluster.conf"
`sed -i -e "/^.*<VirtualHost /s/ .*/  <VirtualHost  ${WEBALIAS}:6666>/" /opt/rh/jbcs-httpd24/root/etc/httpd/conf.d/mod_cluster.conf`
sleep 10

chown -R ${WEBUSR}:${WEBGRP} /opt/rh/jbcs-httpd24 
chmod -R 775 /opt/rh/jbcs-httpd24

systemctl enable jbcs-httpd24-httpd
sleep 10
systemctl restart jbcs-httpd24-httpd
sleep 10
systemctl status jbcs-httpd24-httpd
sleep 10
`sed -i 's/^#PermitRootLogin.*yes\|PermitRootLogin.*yes/PermitRootLogin no/' /etc/ssh/sshd_config`
systemctl restart sshd;
echo "...FINISH INSTALL APACHE JBOSS CORE SERVICE..."

exit 0


