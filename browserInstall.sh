#!/bin/bash

# script to install/setup dependencies for the UCSC genome browser CGIs
# call it like this as root from a command line: bash browserInstall.sh

# you can easily debug this script with 'bash -x browserInstall.sh', it 
# will show all commands then

set -u -e -o pipefail # fail on unset vars and all errors, also in pipes

# ---- GLOBAL DEFAULT SETTINGS ----

# main directory where CGI-BIN and htdocs are downloaded to
APACHEDIR=/usr/local/apache

# apache config file
APACHECONFURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/apache.conf

# genome browser default config file
HGCONFURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/hg.conf

# mysql data directory 
MYSQLDIR=/var/lib/mysql

# mysql admin binary, different path on OSX
MYSQLADMIN=mysqladmin

# the mysql root password is tracked via this variable
# you cannot set it in this script here, just write it to ~root/.my.cnf or
# run the script, it will generate a default ~root/.my.cnf for you
SET_MYSQL_ROOT="0"

# command to ask user to press a key, can be removed with -b
#WAITKEY='echo Please press any key... ; read -n 1 -s ; echo'

# default download server, can be changed with -a
HGDOWNLOAD='hgdownload.cse.ucsc.edu'

# default GBDB dir
GBDBDIR=/gbdb

# udr binary URL
UDRURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/udr

# rsync is a variable so it can be udr
RSYNC=rsync

# by default, most ENCODE files are not downloaded
RSYNCOPTS="--include=wgEncodeGencode* --include=wgEncodeBroadHistone* --include=wgEncodeReg* --include=wgEncodeAwg* --include=wgEncode*Mapability* --exclude=wgEncode*"
# alternative?
# --include='*/' --exclude='wgEncode*.bam' hgdownload.soe.ucsc.edu::gbdb/hg19/ ./  -h

# a flagfile to indicate that the cgis were installed successfully
COMPLETEFLAG=/usr/local/apache/cgiInstallComplete.flag

# ---- END GLOBAL DEFAULT SETTINGS ----

# --- error handling --- 
function errorHandler ()
{
    echo Error: the UCSC Genome Browser installation script failed with an error
    echo You can run it again with '"bash -x '$0'"' to see what failed.
    echo You can then send us an email with the error message.
    exit $?
}

# three types of data can be remote: mysql data and gbdb data 
# SHOW TABLES results can be cached remotely. All three are 
# deactivated with the following:
function goOffline ()
{
      # first make sure we do not have them commented out already
      sed -i 's/^#slow-db\./slow-db\./g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^#gbdbLoc1=/gbdbLoc1=/g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^#gbdbLoc2=/gbdbLoc2=/g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^#showTableCache=/showTableCache=/g' $APACHEDIR/cgi-bin/hg.conf

      # now comment them out
      sed -i 's/^slow-db\./#slow-db\./g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^gbdbLoc1=/#gbdbLoc1=/g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^gbdbLoc2=/#gbdbLoc2=/g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^showTableCache=/#showTableCache=/g' $APACHEDIR/cgi-bin/hg.conf
}

# wait for a key press
function waitKey ()
{
    echo
    echo Press any key to continue or CTRL-C to abort.
    read -n 1 -s
    echo
}

# oracle's mysql install e.g. on redhat distros does not secure mysql by default, so do this now
# this is copied from Oracle's original script, on centos /usr/bin/mysql_secure_installation
function secureMysql ()
{
        echo
        echo Securing the Mysql install by removing the test user, restricting root
        echo logins to localhost and dropping the database named test.
        waitKey
        # remove anonymous test users
        mysql -e 'DELETE FROM mysql.user WHERE User="";'
        # remove remote root login
        mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        # removing test database
        mysql -e "DROP DATABASE IF EXISTS test;"
        mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
        mysql -e "FLUSH PRIVILEGES;"
}

# When we install Mysql, make sure we do not have an old .my.cnf lingering around
function moveAwayMyCnf () 
{
if [ -f ~root/.my.cnf ]; then
   echo
   echo Mysql is going to be installed, but the file ~root/.my.cnf already exists
   echo The file will be renamed to .my.cnf.old so it will not interfere with the
   echo installation.
   waitKey
   mv ~root/.my.cnf ~root/.my.cnf.old
fi
}

# On OSX, we have to compile everything locally
function setupCgiOsx () 
{
    echo
    echo Now downloading the UCSC source tree into $APACHEDIR/kent
    echo The compiled binaries will be installed into $APACHEDIR/cgi-bin
    echo HTML files will be copied into $APACHEDIR/htdocs
    waitKey

    export MACHTYPE=$(uname -m)
    export MYSQLINC=`mysql_config --include | sed -e 's/^-I//g'`
    export MYSQLLIBS=`mysql_config --libs`

    cd $APACHEDIR
    # get the kent src tree
    if [ ! -d kent ]; then
       wget http://hgdownload.cse.ucsc.edu/admin/jksrc.zip
       unzip jksrc.zip
       rm -f jksrc.zip
    fi

    # get samtools patched for UCSC and compile it
    cd kent
    if [ ! -d samtabix ]; then
       git clone http://genome-source.cse.ucsc.edu/samtabix.git
    else
       cd samtabix
       git pull
       cd ..
    fi

    cd samtabix
    make

    # now compile the genome browser CGIs
    export USE_SAMTABIX=1
    export SAMTABIXDIR=$APACHEDIR/kent/samtabix
    cd $APACHEDIR/kent/src
    make libs

    make alpha CGI_BIN=$APACHEDIR/cgi-bin BINDIR=/usr/local/bin
    cd hg/htdocs
    make DOCUMENTROOT=$APACHEDIR/cgi-bin 

}
# --- error handler end --- 

# START OF SCRIPT 

if [[ "$EUID" != "0" ]]; then
  echo "This script must be run as root or with sudo like this:"
  echo "sudo -H $0"
  exit 1
fi

# On Debian and OSX, sudo by default does not update the HOME variable (hence the -H option above)
if [[ "$SUDO_USER" != "" ]]; then
   export HOME=~root
fi

trap errorHandler ERR

# OPTION PARSING

while getopts ":bauehof" opt; do
  case $opt in
    h)
      echo $0 '[options] [assemblyList] - UCSC genome browser install script'
      echo
      echo parameters:
      echo   'no parameter       - setup Apache and Mysql, do not download any assembly'
      echo   '<assemblyList>     - download Mysql + /gbdb files for a space-separated'
      echo   '                     list of genomes'
      echo
      echo example:
      echo   bash $0 hg19 mm9    - install Genome Browser, download hg19 and mm9, switch to
      echo                         offline mode '(see the -o option)'
      echo
      echo options:
      echo '  -a   - use alternative download server at SDSC'
      echo '  -b   - batch mode, do not prompt for key presses'
      echo '  -e   - when downloading hg19, download all ENCODE files. By default, only'
      echo '         our recommended selection of best-of-ENCODE files is downloaded.'
      echo '  -u   - use UDR (fast UDP) file transfers for the download.'
      echo '         Requires at least one open UDP incoming port 9000-9100.'
      echo '  -o   - offline-mode. Remove all statements from hg.conf that allow loading'
      echo '         data on-the-fly from the UCSC download server. Requires that you have'
      echo '         downloaded at least one assembly. Default if at least one assembly has'
      echo '         been specified.'
      echo '  -f   - on-the-fly mode. Change hg.conf to allow loading data through the'
      echo '         internet, if it is not available locally. The default mode unless an.'
      echo '         assembly has been provided during install'
      echo '  -h   - this help message'
      exit 0
      ;;
    b)
      function waitKey {
          echo
      }
      ;;
    a)
      HGDOWNLOAD=hgdownload-sd.sdsc.edu
      ;;
    e)
      RSYNCOPTS=""
      ;;
    u)
      RSYNC="/usr/local/bin/udr rsync"
      ;;
    o)
      if [ ! -f $APACHEDIR/cgi-bin/hg.conf ]; then
         echo Please install a browser first, then switch the data loading mode.
      fi

      goOffline
      echo $APACHEDIR/cgi-bin/hg.conf was modified. 
      echo Offline mode: data is loaded only from the local Mysql database and file system.
      echo Use the parameter -f to switch to on-the-fly mode.
      exit 0
      ;;
    f)
      if [ ! -f $APACHEDIR/cgi-bin/hg.conf ]; then
         echo Please install a browser first, then switch the data loading mode.
      fi

      # allow on-the-fly loading of sql, file data and allow local table name caching
      sed -i 's/^#slow-db\./slow-db\./g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^#gbdbLoc1=/gbdbLoc1=/g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^#gbdbLoc2=/gbdbLoc2=/g' $APACHEDIR/cgi-bin/hg.conf
      sed -i 's/^#showTableCache=/showTableCache=/g' $APACHEDIR/cgi-bin/hg.conf

      echo $APACHEDIR/cgi-bin/hg.conf was modified. 
      echo On-the-fly mode activated: data is loaded from UCSC when not present locally.
      echo Use the parameter -o to switch to offline mode.
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done
# reset the $1, etc variables after getopts
shift $(($OPTIND - 1))

# detect the OS version, linux distribution
unameStr=`uname`
DIST=none

if [[ "$unameStr" == MINGW32_NT* ]] ; then
    echo Sorry Windows/CYGWIN is not supported
    exit 1

elif [[ "$unameStr" == Darwin* ]]; then
    OS=OSX
    DIST=OSX
    VER=`sw_vers -productVersion`
    APACHECONFDIR=/opt/local/apache2/conf # only used by the OSX-spec part
    APACHECONF=$APACHECONFDIR/001-browser.conf
    APACHEUSER=_www
    MYSQLDIR=/opt/local/var/db/mysql56/

elif [[ $unameStr == Linux* ]] ; then
    OS=linux
    if [ -f /etc/debian_version ] ; then
        DIST=debian  # Ubuntu, etc
        VER=$(cat /etc/debian_version)
        APACHECONF=/etc/apache2/sites-available/001-browser.conf
        APACHEUSER=www-data
    elif [[ -f /etc/redhat-release ]] ; then
        DIST=redhat
        VER=$(cat /etc/redhat-release)
        APACHECONF=/etc/httpd/conf.d/001-browser.conf
        APACHEUSER=apache
    elif [[ -f /etc/os-release ]]; then
        # line looks like this on Amazon AMI Linux: 'ID_LIKE="rhel fedora"'
        source /etc/os-release
        if [[ $ID_LIKE == rhel* ]]; then
                DIST=redhat
                VER=$VERSION
                APACHECONF=/etc/httpd/conf.d/001-browser.conf
                APACHEUSER=apache
        fi
    fi
fi

if [ "$DIST" == "none" ]; then
    echo Sorry, unable to detect your linux distribution. 
    echo Currently only Debian/Redhat-like distributions are supported.
    exit 3
fi

# UPDATE MODE, parameter "update": This is not for the initial install, but
# later, when the user wants to update the browser. This can be used from
# cronjobs.
# This currently does NOT update the Mysql databases

if [ "${1:-}" == "update" ]; then
   # update the CGIs
   rsync -avzP --delete --exclude hg.conf $HGDOWNLOAD::cgi-bin/ $APACHEDIR/cgi-bin/ --exclude RNAplot
   # update the html docs
   rsync -avzP --delete --exclude trash $HGDOWNLOAD::htdocs/ $APACHEDIR/htdocs/ 
   # assign all downloaded files to a valid user. 
   chown -R $APACHEUSER:$APACHEUSER $APACHEDIR/*
   echo update finished
   exit 10
fi

# Start apache/mysql setup if the script is run without a parameter

if [ ! -f $COMPLETEFLAG ]; then
    echo '--------------------------------'
    echo UCSC Genome Browser installation
    echo '--------------------------------'
    echo Detected OS: $OS/$DIST, $VER
    echo 
    echo This script will go through three steps:
    echo "1 - setup apache and mysql, open port 80, deactivate SELinux"
    echo "2 - copy CGI binaries into $APACHEDIR"
    echo "3 - optional: download genome assembly databases into mysql and /gbdb"
    echo
    echo This script will now install and configure Mysql and Apache if they are not yet installed. 
    echo "Your distribution's package manager will be used for this."
    echo If Mysql is not installed yet, it will be installed, secured and a root password defined.
    echo
    echo This script will also deactivate SELinux if active and open port 80/http.
    waitKey
fi

# -----  OSX - SPECIFIC part -----
if [[ "$DIST" == "OSX" ]]; then
   if port usage 2> /dev/null; then
       echo Found MacPorts
   else
       echo
       echo Error: Could not find MacPorts or MacPorts is not working. Please install it from 
       echo https://www.macports.org/install.php
       echo
       echo If you have MacPorts installed before but upgraded your OSX version recently, 
       echo follow the instructions at https://trac.macports.org/wiki/Migration
       echo
       echo Check that the '"port"' command works. Then restart this script.
       echo
       exit 102
   fi

   # in case that it is running, try to stop Apple's personal web server, we need access to port 80
   # ignore any error messages
   if [ -f /usr/sbin/apachectl ]; then
       /usr/sbin/apachectl stop 2> /dev/null || true
       launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist 2> /dev/null || true
   fi

   # install wget
   if port installed wget | grep None > /dev/null; then
       port install wget
   fi

   # install apache2
   if port installed apache2 | grep None > /dev/null; then
       port install apache2
   fi

   # include browser config from main apache config
   if cat $APACHECONFDIR/httpd.conf | grep '^Include conf/001-browser.conf' 2> /dev/null; then
       echo Browser config file is included from $APACHECONFDIR/httpd.conf
   else
       echo Appending browser config include line to $APACHECONFDIR/httpd.conf
       echo Include conf/001-browser.conf >> $APACHECONFDIR/httpd.conf
   fi

   # download browser config
   if [[ ! -f $APACHECONF ]]; then
      echo Creating $APACHECONF
      wget -q $APACHECONFURL -O $APACHECONF
      # to avoid the error message message that htdocs does not exist
      mkdir -p /usr/local/apache/htdocs
   fi

   # ignore errors, in case that apache2 is already running
   port load apache2 || true

   # MYSQL INSTALL, mostly copied from https://trac.macports.org/wiki/howto/MySQL

   if port installed mysql56-server | grep None > /dev/null; then
      moveAwayMyCnf
      # install mysql
      port install mysql56-server
   fi

   # add mysql binaries to the PATH
   port select mysql mysql56

   if [ ! -d /opt/local/var/db/mysql56/mysql ]; then
       echo
       echo Creating the basic Mysql databases and securing them
       waitKey
       # create the basic DBs
       sudo -u _mysql mysql_install_db
       # adapt permissions
       sudo chown -R _mysql:_mysql /opt/local/var/db/mysql56/
       sudo chown -R _mysql:_mysql /opt/local/var/run/mysql56/ 
       sudo chown -R _mysql:_mysql /opt/local/var/log/mysql56/ 
       # secure the mysql install
       secureMysql
       # set a random root password later
       SET_MYSQL_ROOT=1
   fi

   # load mysql now and on boot, ignore errors, in case it's already running
   port load mysql56-server || true

   # make sure to use macports specific mysqladmin
   MYSQLADMIN=/opt/local/lib/mysql56/bin/mysqladmin
    
   echo OSX specific part of the installation successful

# -----  DEBIAN / UBUNTU - SPECIFIC part
elif [[ "$DIST" == "debian" ]]; then
    # update repos
    if [ ! -f /tmp/browserInstall.aptGetUpdateDone ]; then
       echo Running apt-get update
       apt-get update
       touch /tmp/browserInstall.aptGetUpdateDone
    fi

    # use dpkg to check if ghostscript is installed
    if dpkg-query -W ghostscript 2>&1 | grep "no packages found" > /dev/null; then 
        echo
        echo Installing ghostscript
        waitKey
        apt-get --assume-yes install ghostscript
    fi

    if [ ! -f $APACHECONF ]; then
        echo
        echo Now installing Apache2.
        echo "Apache's default config /etc/apache2/sites-enable/000-default will be"
        echo "deactivated. A new configuration $APACHECONF will be added and activated."
        echo The apache modules SSI and CGI and authz_core will be activated.
        waitKey

        # apache and mysql are absolutely required
        # ghostscript is required for PDF output
        apt-get --assume-yes install apache2 ghostscript
    
        # gmt is not required. install fails if /etc/apt/sources.list does not contain
        # a 'universe' repository mirror. Can be safely commented out. Only used
        # for world maps of alleles on the dbSNP page.
        # apt-get install gmt
        
        # activate required apache2 modules
        a2enmod include # we need SSI and CGIs
        a2enmod cgid
        a2enmod authz_core # see $APACHECONF why this is necessary
        #a2dismod deflate # allows to partial page rendering in firefox during page load
        
        # download the apache config for the browser and restart apache
        if [ ! -f $APACHECONF ]; then
          echo Creating $APACHECONF
          wget -q $APACHECONFURL -O $APACHECONF
          a2ensite 001-browser
          a2dissite 000-default
          service apache2 restart
        fi
    fi

    if [[ ! -f /usr/sbin/mysqld ]]; then
        echo
        echo Now installing the Mysql server. 
        echo The root password will be set to a random string and will be written
        echo to the file /root/.my.cnf so root does not have to provide a password on
        echo the command line.
        waitKey
        moveAwayMyCnf

        # do not prompt in apt-get, will set an empty mysql root password
        export DEBIAN_FRONTEND=noninteractive
        apt-get --assume-yes install mysql-server
        # flag so script will set mysql root password later to a random value
        SET_MYSQL_ROOT=1
    fi

# ----- END OF DEBIAN SPECIFIC PART

# ----- REDHAT / FEDORA / CENTOS specific part
elif [[ "$DIST" == "redhat" ]]; then
    echo 
    echo Installing wget, EPEL, ghostscript, libpng
    waitKey
    # make sure we have wget and EPEL and ghostscript
    yum -y install wget epel-release ghostscript

    # centos 7 and fedora 20 do not provide libpng by default
    if ldconfig -p | grep libpng12.so > /dev/null; then
        echo libpng12 found
    else
        yum -y install libpng12
    fi
    
    # install apache if not installed yet
    if [ ! -f /usr/sbin/httpd ]; then
        echo
        echo Installing Apache and making it start on boot
        waitKey
        yum -y install httpd
        # start apache on boot
        chkconfig --level 2345 httpd on
        service httpd start
    else
        echo Apache already installed
    fi
    
    # download the apache config
    if [ ! -f $APACHECONF ]; then
        echo
        echo Creating the Apache2 config file $APACHECONF
        waitKey
        wget -q $APACHECONFURL -O $APACHECONF
    fi
    service httpd restart

    # this triggers an error if rpmforge is not installed
    # but if rpmforge is installed, we need the option
    # psxy is not that important, we just skip it for now
    #yum -y install GMT hdf5 --disablerepo=rpmforge
    
    if [ -f /etc/init.d/iptables ]; then
       echo Opening port 80 for incoming connections to Apache
       waitKey
       iptables -I INPUT 1 -i eth0 -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
       service iptables save
    fi
    
    # MYSQL INSTALL ON REDHAT, quite involved, as MariaDB is increasingly the default

    # centos7 provides only a package called mariadb-server
    if yum list mysql-server 2> /dev/null ; then
        MYSQLPKG=mysql-server
    elif yum list mariadb-server 2> /dev/null ; then
        MYSQLPKG=mariadb-server
    else
        echo Cannot find a mysql-server package in the current yum repositories
        exit 100
    fi
    
    # even mariadb packages currently call their binary /usr/bin/mysqld_safe
    if [ ! -f /usr/bin/mysqld_safe ]; then
        echo 
        echo Installing the Mysql or MariaDB server and make it start at boot.
        waitKey

        moveAwayMyCnf
        yum -y install $MYSQLPKG
    
        # Fedora 20 names the package mysql-server but it actually contains mariadb
        MYSQLD=mysqld
        MYSQLVER=`mysql --version`
        if [[ $MYSQLVER =~ "MariaDB" ]]; then
            MYSQLD=mariadb
        fi
            
        # start mysql on boot
        chkconfig --level 2345 $MYSQLD on 

        # start mysql now
        /sbin/service $MYSQLD start

        secureMysql
        SET_MYSQL_ROOT=1
    else
        echo Mysql already installed
    fi
fi
    
# ---- END OF REDHAT SPECIFIC PART

if [[ "${SET_MYSQL_ROOT}" == "1" ]]; then
   # first check if an old password still exists in .my.cnf
   if [ -f ~root/.my.cnf ]; then
       echo ~root/.my.cnf already exists, you might want to remove this file
       echo and restart the script if an error message appears below.
       echo
   fi

   # generate a random char string
   # OSX's tr is quite picky with unicode, so change LC_ALL temporarily
   MYSQLROOTPWD=`cat /dev/urandom | LC_ALL=C tr -dc A-Z-a-z-0-9 | head -c8` || true
   # paranoia check
   if [[ "$MYSQLROOTPWD" == "" ]]; then
       echo Error: could not generate a random Mysql root password
       exit 111
   fi

   echo
   echo The Mysql server was installed and therefore has an empty root password.
   echo Trying to set mysql root password to the randomly generated string '"'$MYSQLROOTPWD'"'

   # now set the mysql root password
   if $MYSQLADMIN -u root password $MYSQLROOTPWD; then
       # and write it to my.cnf
       if [ ! -f ~root/.my.cnf ]; then
           echo
           echo Writing password to /root/.my.cnf so root does not have to provide a password on the 
           echo command line.
           echo '[client]' >> ~root/.my.cnf
           echo user=root >> ~root/.my.cnf
           echo password=${MYSQLROOTPWD} >> ~root/.my.cnf
           chmod 600 ~root/.my.cnf
           waitKey
        else
           echo ~root/.my.cnf already exists, not changing it.
        fi 
   else
       echo Could not connect to mysql to set the root password to $MYSQLROOTPWD.
       echo A root password must have been set by a previous installation.
       echo Please reset the root password to an empty password by following these
       echo instructions: http://dev.mysql.com/doc/refman/5.0/en/resetting-permissions.html
       echo Then restart the script.
       echo Or, if you remember the old root password, write it to a file ~root/.my.cnf, 
       echo create three lines
       echo '[client]'
       echo user=root
       echo password=PASSWORD
       echo run chmod 600 ~root/.my.cnf and restart this script.
       exit 123
   fi

fi

# before we do anything else with mysql
# we need to check if we can access it. 
# so test if we can connect to the mysql server
# need to temporarily deactivate error abort mode, in case mysql cannot connect

if mysql -e "SHOW TABLES;" mysql 2> /dev/null > /dev/null; then
    true
else
    echo "ERROR:"
    echo "Cannot connect to mysql database server, a root password has probably been setup before."
    # create a little basic .my.cnf for the current root user
    # so the mysql root password setup is easier
    if [ ! -f ~root/.my.cnf ]; then
       echo '[client]' >> ~root/.my.cnf
       echo user=root >> ~root/.my.cnf
       echo password=YOURMYSQLPASSWORD >> ~root/.my.cnf
       chmod 600 ~root/.my.cnf
       echo
       echo A file ${HOME}/.my.cnf was created with default values
       echo Edit the file ${HOME}/.my.cnf and replace YOURMYSQLPASSWORD with the mysql root password that you
       echo defined during the mysql installation.
    else
       echo
       echo A file ${HOME}/.my.cnf already exists
       echo Edit the file ${HOME}/.my.cnf and make sure there is a '[client]' section
       echo and under it at least two lines with 'user=root' and 'password=YOURMYSQLPASSWORD'.
    fi
       
    echo "Then run this script again."
    exit 200
fi
   
# DETECT AND DEACTIVATE SELINUX
if [ -f /sbin/selinuxenabled ]; then
    if /sbin/selinuxenabled; then
       echo
       echo The Genome Browser requires that SELINUX is deactivated.
       echo Deactivating it now.
       waitKey
       # deactivate selines until next reboot
       setenforce 0
       # permanently deactivate after next reboot
       sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux
    fi
fi

# Download over own statically compiled udr binary
if [[ ! -f /usr/local/bin/udr && "$RSYNC" = *udr* ]]; then
  echo 'Downloading download-tool udr (UDP-based rsync with multiple streams) to /usr/local/bin/udr'
  waitKey
  wget -q $UDRURL -O /usr/local/bin/udr
  chmod a+x /usr/local/bin/udr
fi

# CGI DOWNLOAD AND HGCENTRAL MYSQL DB SETUP

if [ ! -f $COMPLETEFLAG ]; then
    # test if an apache file is already present
    if [ -f "$APACHEDIR" ]; then
        echo error: please remove the file $APACHEDIR, then restart the script with "$0 download".
        exit 249
    fi

    # check if /usr/local/apache is empty
    # on OSX, we had to create htdocs, so skip this check there
    if [ -d "$APACHEDIR" -a "$OS" != "OSX" ]; then
        echo error: the directory $APACHEDIR already exists.
        echo This installer has to overwrite it, so please move it to a different name
        echo or remove it. Then start the installer again with "bash $0"
        exit 250
    fi

    # -------------------
    # Mysql setup
    # -------------------
    echo
    echo Creating Mysql databases customTrash, hgTemp and hgcentral
    waitKey
    mysql -e 'CREATE DATABASE IF NOT EXISTS customTrash;'
    mysql -e 'CREATE DATABASE IF NOT EXISTS hgcentral;'
    mysql -e 'CREATE DATABASE IF NOT EXISTS hgTemp;'
    wget -q http://$HGDOWNLOAD/admin/hgcentral.sql -O - | mysql hgcentral
    # the blat servers don't have fully qualified domain names in the download data
    mysql hgcentral -e 'UPDATE blatServers SET host=CONCAT(host,".cse.ucsc.edu");'
    
    echo
    echo "Will now grant permissions to browser database access users:"
    echo "User: 'browser', password: 'genome' - full database access permissions"
    echo "User: 'readonly', password: 'access' - read only access for CGI binaries"
    echo "User: 'readwrite', password: 'update' - readwrite access for hgcentral DB"
    waitKey
    
    #  Full access to all databases for the user 'browser'
    #       This would be for browser developers that need read/write access
    #       to all database tables.  
    mysql -e "GRANT SELECT, INSERT, UPDATE, DELETE, FILE, "\
"CREATE, DROP, ALTER, CREATE TEMPORARY TABLES on *.* TO browser@localhost "\
"IDENTIFIED BY 'genome';"
    
    # FILE permission for this user to all databases to allow DB table loading with
    #       statements such as: "LOAD DATA INFILE file.tab"
    # For security details please read:
    #       http://dev.mysql.com/doc/refman/5.1/en/load-data.html
    #       http://dev.mysql.com/doc/refman/5.1/en/load-data-local.html
    mysql -e "GRANT FILE on *.* TO browser@localhost IDENTIFIED BY 'genome';" 
    
    #   Read only access to genome databases for the browser CGI binaries
    mysql -e "GRANT SELECT, CREATE TEMPORARY TABLES on "\
"*.* TO readonly@localhost IDENTIFIED BY 'access';"
    mysql -e "GRANT SELECT, INSERT, CREATE TEMPORARY TABLES on hgTemp.* TO "\
"readonly@localhost IDENTIFIED BY 'access';"
    
    # Readwrite access to hgcentral for browser CGI binaries to maintain session state
    mysql -e "GRANT SELECT, INSERT, UPDATE, "\
"DELETE, CREATE, DROP, ALTER on hgcentral.* TO readwrite@localhost "\
"IDENTIFIED BY 'update';"
    
    # create /gbdb and let the apache user write to it
    # hgConvert will download missing liftOver files on the fly and needs write
    # write access
    mkdir -p $GBDBDIR
    chown $APACHEUSER:$APACHEUSER $GBDBDIR
    
    # the custom track database needs it own user and permissions
    mysql -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,ALTER,INDEX "\
"on customTrash.* TO ctdbuser@localhost IDENTIFIED by 'ctdbpassword';"
    
    # by default hgGateway needs an empty hg19 database, will crash otherwise
    mysql -e 'CREATE DATABASE IF NOT EXISTS hg19'
    
    mysql -e "FLUSH PRIVILEGES;"
    
    # -------------------
    # CGI installation
    # -------------------
    echo
    echo Now creating /usr/local/apache and downloading contents from UCSC
    waitKey
    
    # create apache directories: HTML files, CGIs, temporary and custom track files
    mkdir -p $APACHEDIR/htdocs $APACHEDIR/cgi-bin $APACHEDIR/trash $APACHEDIR/trash/customTrash
    
    # the CGIs create links to images in /trash which need to be accessible from htdocs
    cd $APACHEDIR/htdocs 
    ln -fs ../trash
    
    # download the sample hg.conf into the cgi-bin directory
    wget $HGCONFURL -O $APACHEDIR/cgi-bin/hg.conf
    
    # redhat distros have the same default socket location set in mysql as
    # in our binaries. To allow mysql to connect, we have to remove the socket path.
    # Also change the psxy path to the correct path for redhat, /usr/bin/
    if [ "$DIST" == "redhat" ]; then
       sed -i "/socket=/s/^/#/" $APACHEDIR/cgi-bin/hg.conf
       sed -i "/^hgc\./s/.usr.lib.gmt.bin/\/usr\/bin/" $APACHEDIR/cgi-bin/hg.conf
    elif [ "$DIST" == "OSX" ]; then
       # in OSX also no need to specify sockets
       sed -i "/socket=/s/^/#/" $APACHEDIR/cgi-bin/hg.conf
    fi
    
    # download the CGIs
    if [[ "$OS" == "OSX" ]]; then
        setupCgiOsx
    else
        # don't download RNAplot, it's a 32bit binary that won't work
        # this means that hgGene cannot show RNA structures but that's not a big issue
        $RSYNC -avzP --exclude RNAplot $HGDOWNLOAD::cgi-bin/ $APACHEDIR/cgi-bin/
        
        # download the html docs
        $RSYNC -avzP $HGDOWNLOAD::htdocs/ $APACHEDIR/htdocs/ 
    fi
    
    # assign all files just downloaded to a valid user. 
    # This also allows apache to write into the trash dir
    chown -R $APACHEUSER:$APACHEUSER $APACHEDIR/*
    
    touch $COMPLETEFLAG

    if [ "${1:-}" == "" ]; then
       echo
       echo Install complete. You should now be able to point your web browser to this machine
       echo and use your UCSC Genome Browser mirror.
       echo
       echo Notice that this mirror is still configured to use Mysql and data files loaded
       echo through the internet from UCSC. From most locations on the world, this is very slow.
       echo
       echo To speed up the installation, you need to download genome data to the local
       echo disk. To download a genome assembly and all its files now, call this script again with
       echo the parameters '"<assemblyName1> <assemblyName2> ..."', e.g. '"'bash $0 mm10 hg19'"'
       echo 
       exit 0
    fi
    
fi

# GENOME DOWNLOAD

DBS=${*:1}

echo
echo Downloading databases $DBS plus hgFixed/proteome/go from the UCSC download server
echo
echo Determining download file size... please wait...

# use rsync to get total size of files in directories and sum the numbers up with awk
for db in $DBS proteome uniProt go hgFixed; do
    rsync -avn $HGDOWNLOAD::mysql/$db/ $MYSQLDIR/$db/ $RSYNCOPTS | grep ^'total size' | cut -d' ' -f4 | tr -d ', ' 
done | awk '{ sum += $1 } END { print "Required space in '$MYSQLDIR':", sum/1000000000, "GB" }'

for db in $DBS; do
    rsync -avn $HGDOWNLOAD::gbdb/$db/ $GBDBDIR/$db/ $RSYNCOPTS | grep ^'total size' | cut -d' ' -f4 | tr -d ','
done | awk '{ sum += $1 } END { print "Required space in '$GBDBDIR':", sum/1000000000, "GB" }'

echo
echo Currently available disk space on this system:
df -h 
echo 
waitKey

# now do the actual download of mysql files
for db in $DBS proteome uniProt go hgFixed; do
   echo Downloading Mysql files for DB $db
   $RSYNC --progress -avzp $RSYNCOPTS $HGDOWNLOAD::mysql/$db/ $MYSQLDIR/$db/ 
   chown -R mysql:mysql $MYSQLDIR/$db
done

# download /gbdb files
for db in $DBS; do
   echo Downloading $GBDBDIR files for DB $db
   mkdir -p $GBDBDIR
   $RSYNC --progress -avzp $RSYNCOPTS $HGDOWNLOAD::gbdb/$db/ $GBDBDIR/$db/
   chown -R $APACHEUSER:$APACHEUSER $GBDBDIR/$db
done

goOffline # modify hg.conf and remove all statements that use the UCSC download server

echo
echo Install complete. You should now be able to point your web browser to this machine
echo and use your UCSC Genome Browser mirror.
echo It seems that the address to contact this machine is 
# http://unix.stackexchange.com/questions/22615/how-can-i-get-my-external-ip-address-in-bash
echo http://`wget http://icanhazip.com -O - -q`
echo 
echo Note that this installation assumes that emails cannot be sent from
echo this machine. New browser user accounts will not receive confirmation emails.
echo To change this, edit the file $APACHEDIR/cgi-bin/hg.conf and modify the settings
echo 'that start with "login.", mainly "login.mailReturnAddr"'.
echo
echo Please send any other questions to the mailing list, genome-mirror@soe.ucsc.edu .
waitKey
