#!/bin/bash
# This script will autostart all opsi services
startsetup="unknown"
setuptries=0
while [ "$startsetup" = "unknown" ] && [ "$setuptries" -lt 4 ]; do
  read  -t10 -r -n1 -p "Do you want to run the setup-script to start using this container? (y/N)" setupresponse
  echo ""
  case "$setupresponse" in
    [yY])
      startsetup="true"
      setuptries=4
      ;;
    [nN])
      startsetup="false"
      setuptries=4
      ;;
    *)
      startsetup="unknown"
      let "setuptries++"
      ;;
  esac
done

/usr/sbin/useradd -m -s /bin/bash $OPSI_USER
echo "$OPSI_USER:$OPSI_PASSWORD" | chpasswd
echo -e "$OPSI_PASSWORD\n$OPSI_PASSWORD\n" | smbpasswd -s -a $OPSI_USER
/usr/sbin/usermod -aG opsiadmin $OPSI_USER
/usr/sbin/usermod -aG pcpatch $OPSI_USER
mkdir /var/run/opsipxeconfd
chown root:opsiadmin /var/run/opsipxeconfd

if [ "$startsetup" = "true" ]; then
  echo "`date` [INFO] Starting setup script"
  echo "`date` [INFO] Please wait..."
  /usr/local/bin/setup.sh
  startsetup="false"
fi
if [ "$startsetup" = "false" ] || [ "$startsetup" = "unknown" ]; then
  date +%s | sha256sum | base64 | head -c 32 | /usr/bin/opsi-admin -d task setPcpatchPassword
  /usr/bin/opsi-setup --set-rights
  echo "`date` [INFO] Starting services"
  /usr/sbin/smbd -D
  /usr/sbin/in.tftpd -v --ipv4 --listen --address :69 --secure /tftpboot/
  /usr/bin/opsiconfd -D start
  /usr/bin/opsipxeconfd start &
  /usr/bin/opsi-setup --auto-configure-samba
  
  re="/(@(annually|yearly|monthly|weekly|daily|hourly|reboot))|(@every (\d+(ns|us|µs|ms|s|m|h))+)|((((\d+,)+\d+|(\d+(\/|-)\d+)|\d+|\*) ?){5,7})/"
  if [[ $OPSI_PACKAGEUPDATER_UPDATE =~ $re ]] ; then
    touch /etc/opsi/opsipackageupdatercron
    echo "$OPSI_PACKAGEUPDATER_UPDATE root opsi-package-updater -v update" > /etc/opsi/opsipackageupdatercron
    echo " ">> /etc/opsi/opsipackageupdatercron
    chmod 744 /etc/opsi/opsipackageupdatercron
    cron -L 7 /etc/opsi/opsipackageupdatercron
  fi

  while true; do
    runningsmbd=$(pgrep smbd)
    if [ -z "$runningsmbd" ]; then
      echo "`date` [ERROR] smbd not running. Starting again..."
      /usr/sbin/smbd -D
    fi
    runningtftpd=$(pgrep in.tftpd)
    if [ -z "$runningtftpd" ]; then
      echo "`date` [ERROR] tftpd not running. Starting again..."
      /usr/sbin/in.tftpd -v --ipv4 --listen --address :69 --secure /tftpboot/
    fi
    runningconfd=$(pgrep opsiconfd)
    if [ -z "$runningconfd" ]; then
      echo "`date` [ERROR] opsiconfd not running. Starting again..."
      /usr/bin/opsiconfd -D start
    fi
    unset runningconfd
    runningpxeconfd=$(pgrep opsipxeconfd)
    if [ -z "$runningpxeconfd" ]; then
      echo "`date` [ERROR] opsipxeconfd not running. Starting again..."
      /usr/bin/opsipxeconfd start &
    fi
    unset runningpxeconfd
    sleep 20
  done
fi
echo "`date` [INFO] Exit"
