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

# command to ask user to press a key, can be removed with -b
WAITKEY='read -n 1 -s'

# default download server, can be changed with -a
HGDOWNLOAD='hgdownload.cse.ucsc.edu'

# default GBDB dir
GBDBDIR=/gbdb

# udr binary URL
UDRURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/udr

# by default, most ENCODE files are not downloaded
RSYNCOPTS="--include wgEncodeGencode* --include wgEncodeRegTfbsClustered* --include wgEncodeRegMarkH3k27ac* --include wgEncodeRegDnaseClustered* --exclude wgEncode*"

# ---- END GLOBAL DEFAULT SETTINGS ----

# --- error handling --- 
function errorHandler ()
{
    echo Error: the UCSC Genome Browser installation script failed with an error
    echo You can run it again with '"bash -x '$0'"' to see what failed.
    echo You can also send us an email with the error message.
    exit $?
}
trap errorHandler ERR

# --- error handler end --- 

# START OF SCRIPT 

if [ "$EUID" -ne 0 ]
  then echo "This script must be run as root"
  exit 1
fi

# OPTION PARSING

while getopts ":b:a:h" opt; do
  case $opt in
    h)
      echo $0 - UCSC genome browser install script
      echo parameters:
      echo   'no parameter       - setup Apache and Mysql'
      echo   'download           - download the CGI scripts'
      echo   'get <databaseList> - download Mysql + /gbdb files for a space-separated'
      echo   '                     list of genomes'
      echo
      echo options:
      echo '  -a   - use alternative download server at SDSC'
      echo '  -b   - batch mode, do not prompt for key presses'
      echo '  -e   - download all ENCODE files. By default, most Encode files are not downloaded.'
      echo '  -u   - use UDR (fast UDP) file transfers for the download. Requires at least one '
      echo '         open UDP incoming port between 9000 - 9100'
      echo '  -h   - this help message'
      exit 0
      ;;
    b)
      WAITKEY='echo'
      ;;
    a)
      HGDOWNLOAD=hgdownload-sd.sdsc.edu
      ;;
    e)
      RSYNCOPTS=""
      ;;
    u)
      if [[ ! -f /usr/local/bin/udr ]]; then
          curl $UDRURL > /usr/local/bin/udr
          chmod a+x /usr/local/bin/udr
      fi
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
if [[ "$unameStr" == "Darwin" ]]; then
    echo Sorry OSX is not supported
    exit 1
elif [[ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]] ; then
    echo Sorry CYGWIN is not supported
    exit 1
fi

if [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]] ; then
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
   chown -R $APACHEUSER.$APACHEUSER $APACHEDIR/*
   echo update finished
   exit 10
fi

# Start apache/mysql setup if the script is run without a parameter

if [[ "$#" == "0" ]]; then
    echo '--------------------------------'
    echo UCSC Genome Browser installation
    echo '--------------------------------'
    echo Detected OS: $OS/$DIST, $VER
    echo 
    echo This script will go through three steps:
    echo "1 - setup apache and mysql, deactivate SELinux, open port 80"
    echo "2 - copy CGI binaries into $APACHEDIR"
    echo "3 - optional: download genome assembly databases into mysql and /gbdb"
    echo
    echo This script will now install and configure Mysql and Apache if they are not yet installed. 
    echo "Your distribution's package manager will be used for this."
    echo If Mysql is not installed yet, you will be asked to enter a new Mysql root password.
    echo It can can be different from the root password of this machine.
    echo
    echo This script will also deactivate SELinux if active and open port 80/http.
    echo Please press any key to continue...
    $WAITKEY
    
    # -----  DEBIAN / UBUNTU - SPECIFIC part
    if [[ "$DIST" == "debian" ]]; then
       # get repo lists
       apt-get update
       # apache and mysql are absolutely required
       apt-get install apache2
       apt-get install mysql-server
       # ghostscript is required for PDF output
       apt-get install ghostscript

       # gmt is not required. install fails if /etc/apt/sources.list does not contain
       # a 'universe' repository mirror. Can be safely commented out. Only used
       # for world maps of alleles on the dbSNP page.
       apt-get install gmt
    
       # activate required modules
       a2enmod include # we need SSI and CGIs
       a2enmod cgid
       a2enmod authz_core # see $APACHECONF why this is necessary
       #a2dismod deflate # allows to partial page rendering in firefox during page load

       # install the apache config for the browser
       if [ ! -f $APACHECONF ]; then
          echo Creating $APACHECONF
          wget -q $APACHECONFURL -O $APACHECONF
          a2ensite 001-browser
          a2dissite 000-default
       fi
       # restart
       service apache2 restart
       # ----- END OF DEBIAN SPECIFIC PART
    
    # ----- REDHAT / FEDORA / CENTOS specific part
    elif [[ "$DIST" == "redhat" ]]; then
        # make sure we have wget and EPEL
        yum -y install wget epel-release

        # install apache if not installed yet
        if [ ! -f /usr/sbin/httpd ]; then
            echo Installing Apache
            yum -y install httpd
            # start apache on boot
            chkconfig --level 2345 httpd on
        else
            echo Apache already installed
        fi
    
        # download the apache config
        if [ ! -f $APACHECONF ]; then
            echo Creating $APACHECONF
            wget -q $APACHECONFURL -O $APACHECONF
        fi
        service httpd restart

        # centos provides only a package called mariadb-server
        if yum list mysql-server 2> /dev/null ; then
            MYSQLPKG=mysql-server
        elif yum list mariadb-server 2> /dev/null ; then
            MYSQLPKG=mariadb-server
        else
            echo Cannot find a mysql-server package in the current yum repos
            exit 100
        fi

        if [ ! -f /usr/bin/mysqld_safe ]; then
            echo Installing Mysql
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
            # redhat distros do not secure mysql by default
            # so define root password, remove test accounts, etc
            mysql_secure_installation
        else
            echo Mysql already installed
        fi
    
        # centos 7 and fedora 20 do not provide libpng by default
        if ldconfig -p | grep libpng12.so > /dev/null; then
            echo libpng12 found
        else
            yum -y install libpng12
        fi

        yum -y install ghostscript

        # this triggers an error if rpmforge is not installed
        # but if rpmforge is installed, we need the option
        # psxy is not that important, we just skip it for now
        #yum -y install GMT hdf5 --disablerepo=rpmforge

        if [ -f /etc/init.d/iptables ]; then
           echo Opening port 80 for incoming connections
           iptables -I INPUT 1 -i eth0 -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
           service iptables save
        fi
        # ---- END OF REDHAT SPECIFIC PART
    fi

    # DETECT AND DEACTIVATE SELINUX
    if [ -f /sbin/selinuxenabled ]; then
        if /sbin/selinuxenabled; then
           echo
           echo The Genome Browser requires that SELINUX is deactivated.
           echo Deactivating it now.
           echo Please press any key...
           $WAITKEY
           setenforce 0
           sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux
        fi
    fi

    # create a little basic .my.cnf for the current root user
    # so the mysql root password setup is easier
    if [ ! -f ~/.my.cnf ]; then
       echo '[client]' >> ~/.my.cnf
       echo user=root >> ~/.my.cnf
       echo password=YOURMYSQLPASSWORD >> ~/.my.cnf
       chmod 600 ~/.my.cnf

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

    echo "Then run this script again with the parameter download (bash $0 download) to continue."
    exit 0
fi

# MYSQL CONFIGURATION and CGI DOWNLOAD

if [ "${1:-}" == "download" ]; then
    echo --------------------------------
    echo UCSC Genome Browser installation
    echo --------------------------------
    echo Detected OS: $OS/$DIST, $VER
    echo 
    # test if the apache dir is already present
    if [ -f "$APACHEDIR" ]; then
        echo error: please remove the file $APACHEDIR, then restart the script with "$0 download".
        exit 249
    fi

    if [ -d "$APACHEDIR" ]; then
        echo error: the directory $APACHEDIR already exists.
        echo This installer has to overwrite it, so please move it to a different name
        echo or remove it. Then start the installer again with "$0 download"
        exit 250
    fi

    # test if we can connect to the mysql server
    # need to temporarilydeactivate error abort mode, in case mysql cannot connect
    set +e 
    mysql -e "show tables;" mysql > /dev/null 2>&1
    if [ "$?" -ne 0 ]; then
            echo "Cannot connect to mysql database server."
            echo "Edit ${HOME}/.my.cnf and run this script again with the 'mysql' parameter"
            exit 255
    fi
    set -e

    # -------------------
    # Mysql setup
    # -------------------
    echo Creating Mysql databases customTrash, hgTemp and hgcentral
    echo Please press any key...
    $WAITKEY
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
    echo Please press any key...
    $WAITKEY
    
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
    chown $APACHEUSER.$APACHEUSER $GBDBDIR

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
   echo Now creating /usr/local/apache and downloading its files from UCSC via rsync
   echo Please press any key...
   $WAITKEY
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
   fi

   # download the CGIs
   # don't download RNAplot, it's a 32bit binary that won't work
   # this means that hgGene cannot show RNA structures but that's not a big issue
   rsync -avzP $HGDOWNLOAD::cgi-bin/ $APACHEDIR/cgi-bin/ --exclude RNAplot

   # download the html docs
   rsync -avzP $HGDOWNLOAD::htdocs/ $APACHEDIR/htdocs/ 

   # assign all files just downloaded to a valid user. 
   # This also allows apache to write into the trash dir
   chown -R $APACHEUSER.$APACHEUSER $APACHEDIR/*

   echo
   echo Install complete. You should now be able to point your web browser to this machine
   echo and use your UCSC Genome Browser mirror.
   echo Notice that this mirror is still configured to use Mysql and data files loaded
   echo through the internet from UCSC. From most locations on the world, this is very slow.
   echo
   echo If you want to download a genome and all its files now, call this script with
   echo the parameters '"get <name>"', e.g. '"'bash $0 get mm10'"'
   echo 
   echo Also note the installation assumes that emails cannot be sent from
   echo this machine. New browser user accounts will not receive confirmation emails.
   echo To change this, edit the file $APACHEDIR/cgi-bin/hg.conf and modify the settings
   echo 'that start with "login.", mainly "login.mailReturnAddr"'.
   echo
   echo Please send any other questions to the mailing list, genome-mirror@soe.ucsc.edu .
fi

# GENOME DOWNLOAD

if [ "${1:-}" == "get" ]; then
   DBS=${*:2}
   echo
   echo Downloading databases $DBS plus hgFixed/proteome/go from the UCSC download server
   echo
   echo Determining download file size... please wait...
   
   # use rsync to get total size of files in directories and sum the numbers up with awk
   for db in $DBS proteome uniProt go hgFixed; do
       rsync -avn $HGDOWNLOAD::mysql/$db/ $MYSQLDIR/$db/ $RSYNCOPTS | grep ^'total size' | cut -d' ' -f4 | tr -d ', ' 
   done | awk '{ sum += $1 } END { print "Required space in '$GBDBDIR':", sum/1000000000, "GB" }'

   for db in $DBS; do
       rsync -avn $HGDOWNLOAD::gbdb/$db/ $GBDBDIR/$db/ $RSYNCOPTS | grep ^'total size' | cut -d' ' -f4 | tr -d ','
   done | awk '{ sum += $1 } END { print "Required space in '$MYSQLDIR':", sum/1000000000, "GB" }'

   echo
   echo Currently available disk space on this system:
   df -h 
   echo 
   echo Press any key to continue or Ctrl-C to abort
   $WAITKEY

   # now do the actual download
   for db in $DBS proteome uniProt go hgFixed; do
      echo Downloading Mysql files for DB $db
      rsync -avzp $HGDOWNLOAD::mysql/$db/ $MYSQLDIR/$db/ $RSYNCOPTS
      chown -R mysql.mysql $MYSQLDIR/$db
   done

   for db in $DBS; do
      echo Downloading $GBDBDIR files for DB $db
      mkdir -p $GBDBDIR
      rsync -avzp $HGDOWNLOAD::gbdb/$db/ $GBDBDIR/$db/ $RSYNCOPTS
      chown -R $APACHEUSER.$APACHEUSER $GBDBDIR/$db
   done

fi
