#!/bin/bash

# script to install/setup dependencies for the UCSC genome browser CGIs
# call it like this as root from a command line: bash browserInstall.sh

# you can easily debug this script with 'bash -x browserInstall.sh', it 
# will show all commands then

set -u -e -o pipefail # fail on unset vars and all errors, also in pipes

# ---- GLOBAL DEFAULT SETTINGS ----

# directory where CGI-BIN and htdocs are downloaded to
APACHEDIR=/usr/local/apache

# apache config file
APACHECONFURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/apache.conf
# genome browser default config file
HGCONFURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/hg.conf

# mysql data directory 
MYSQLDIR=/var/lib/mysql

# mysql admin binary, different path on OSX
MYSQLADMIN=mysqladmin

# mysql user account, different on OSX
MYSQLUSER=mysql

# mysql client command, will be adapted on OSX
MYSQL=mysql

# flag whether a mysql root password should be set
# the root password is left empty on OSX, as mysql
# there is not listening to a port
SET_MYSQL_ROOT="0"

# default download server, can be changed with -a
HGDOWNLOAD='hgdownload.cse.ucsc.edu'

# default GBDB dir
GBDBDIR=/gbdb

# sed -i has a different syntax on OSX
SEDINPLACE="sed -ri"

# udr binary URL
UDRURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/udr

# rsync is a variable so it can be udr
RSYNC=rsync

# by default, everything is downloaded
RSYNCOPTS=""
# alternative?
# --include='*/' --exclude='wgEncode*.bam' hgdownload.soe.ucsc.edu::gbdb/hg19/ ./  -h

# a flagfile to indicate that the cgis were installed successfully
COMPLETEFLAG=/usr/local/apache/cgiInstallComplete.flag

# on OSX by default we download a pre-compiled package that includes Apache/Mysql/OpenSSL
# change this to 1 to rebuild all of these locally from tarballs
BUILDEXT=${BUILDEXT:-0}
# On OSX, by default download the CGIs as a binary package
# change this to 1 to rebuild CGIs locally from tarball
BUILDKENT=${BUILDKENT:-0}

# URL of a tarball with a the binaries of Apache/Mysql/Openssl
BINPKGURL=http://hgwdev.soe.ucsc.edu/~max/gbInstall/mysqlApacheOSX_10_10.tgz
# URL of tarball with the OSX CGI binaries
CGIBINURL=http://hgwdev.soe.ucsc.edu/~max/gbInstall/kentCgi_OSX_10.10.tgz 
# URL of tarball with a minimal Mysql data directory
MYSQLDBURL=http://hgwdev.soe.ucsc.edu/~max/gbInstall/mysql56Data.tgz
# mysql/apache startup script URL, currently only for OSX
STARTSCRIPTURL=https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserStartup.sh


# ---- END GLOBAL DEFAULT SETTINGS ----

# --- error handling --- 
# add some highlight so it's easier to distinguish our own echoing from the programs we call
function echo2 ()
{
    command echo '|' "$@"
}

# download file to stdout, use either wget or curl
function downloadFile ()
{
url=$1

if which wget 2> /dev/null > /dev/null; then
    wget -nv $1 -O -
else
    echo '| ' $url > /dev/stderr
    curl '-#' $1
fi
}

# download file to stdout, use either wget or curl
function downloadFileQuiet ()
{
url=$1

if which wget 2> /dev/null > /dev/null; then
    wget -q $1 -O -
else
    curl -s $1
fi
}

function errorHandler ()
{
    echo2 Error: the UCSC Genome Browser installation script failed with an error
    echo2 You can run it again with '"bash -x '$0'"' to see what failed.
    echo2 You can then send us an email with the error message.
    exit $?
}

# three types of data can be remote: mysql data and gbdb data 
# SHOW TABLES results can be cached remotely. All three are 
# deactivated with the following:
function goOffline ()
{
      # first make sure we do not have them commented out already
      $SEDINPLACE 's/^#slow-db\./slow-db\./g' $APACHEDIR/cgi-bin/hg.conf
      $SEDINPLACE 's/^#gbdbLoc1=/gbdbLoc1=/g' $APACHEDIR/cgi-bin/hg.conf
      $SEDINPLACE 's/^#gbdbLoc2=/gbdbLoc2=/g' $APACHEDIR/cgi-bin/hg.conf
      $SEDINPLACE 's/^#showTableCache=/showTableCache=/g' $APACHEDIR/cgi-bin/hg.conf

      # now comment them out
      $SEDINPLACE 's/^slow-db\./#slow-db\./g' $APACHEDIR/cgi-bin/hg.conf
      $SEDINPLACE 's/^gbdbLoc1=/#gbdbLoc1=/g' $APACHEDIR/cgi-bin/hg.conf
      $SEDINPLACE 's/^gbdbLoc2=/#gbdbLoc2=/g' $APACHEDIR/cgi-bin/hg.conf
      $SEDINPLACE 's/^showTableCache=/#showTableCache=/g' $APACHEDIR/cgi-bin/hg.conf
}

# wait for a key press
function waitKey ()
{
    echo2
    echo2 Press any key to continue or CTRL-C to abort.
    read -n 1 -s
    echo2
}

# oracle's mysql install e.g. on redhat distros does not secure mysql by default, so do this now
# this is copied from Oracle's original script, on centos /usr/bin/mysql_secure_installation
function secureMysql ()
{
        echo2
        echo2 Securing the Mysql install by removing the test user, restricting root
        echo2 logins to localhost and dropping the database named test.
        waitKey
        # do not parse .my.cnf for this, as we're sure that there is no root password yet
        # MYSQL2=`echo $MYSQL | sed -e 's/ / --no-defaults /'`
        # remove anonymous test users
        $MYSQL -e 'DELETE FROM mysql.user WHERE User="";'
        # remove remote root login
        $MYSQL -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        # removing test database
        $MYSQL -e "DROP DATABASE IF EXISTS test;"
        $MYSQL -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
        $MYSQL -e "FLUSH PRIVILEGES;"
}

# When we install Mysql, make sure we do not have an old .my.cnf lingering around
function moveAwayMyCnf () 
{
if [ -f ~root/.my.cnf ]; then
   echo2
   echo2 Mysql is going to be installed, but the file ~root/.my.cnf already exists
   echo2 The file will be renamed to .my.cnf.old so it will not interfere with the
   echo2 installation.
   waitKey
   mv ~root/.my.cnf ~root/.my.cnf.old
fi
}

# print my various IP addresses to stdout 
function showMyAddress ()
{
echo2
if [[ "$DIST" == "OSX" ]]; then
   echo2 You can browse the genome at http://127.0.0.1:8080
   #/usr/bin/open http://127.0.0.1:8080
else
   echo2 You can now access this server under one of these IP addresses: 
   echo2 From same host:    http://127.0.0.1
   echo2 From same network: http://`ip route get 8.8.8.8 | awk 'NR==1 {print $NF}'`
   echo2 From the internet: http://`downloadFileQuiet http://icanhazip.com`
fi
echo2
}

# On OSX, we have to compile everything locally
function setupCgiOsx () 
{
    if [[ "$BUILDKENT" == "0" ]]; then
        echo2
        echo2 Downloading Precompiled OSX CGI-BIN binaries
        echo2
        cd $APACHEDIR
        downloadFile $CGIBINURL | tar xz
        chown -R $APACHEUSER:$APACHEUSER cgi-bin/
        return
    fi

    echo2
    echo2 Now downloading the UCSC source tree into $APACHEDIR/kent
    echo2 The compiled binaries will be installed into $APACHEDIR/cgi-bin
    echo2 HTML files will be copied into $APACHEDIR/htdocs
    waitKey

    export MYSQLINC=$APACHEDIR/ext/include
    export MYSQLLIBS="/$APACHEDIR/ext/lib/libmysqlclient.a -lz -lc++"
    export SSLDIR=$APACHEDIR/ext/include
    export USE_SSL=1 
    export PNGLIB=$APACHEDIR/ext/lib/libpng.a 
    # careful - PNGINCL is the only option that requires the -I prefix
    export PNGINCL=-I$APACHEDIR/ext/include
    export CGI_BIN=$APACHEDIR/cgi-bin 
    export SAMTABIXDIR=$APACHEDIR/kent/samtabix 
    export USE_SAMTABIX=1
    export SCRIPTS=$APACHEDIR/util
    export BINDIR=$APACHEDIR/util

    export PATH=$BINDIR:$PATH
    mkdir -p $APACHEDIR/util

    cd $APACHEDIR
    # get the kent src tree
    if [ ! -d kent ]; then
       downloadFile http://hgdownload.cse.ucsc.edu/admin/jksrc.zip > jksrc.zip
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

    # compile the genome browser CGIs
    cd $APACHEDIR/kent/src
    make libs
    make cgi-alpha
    cd hg/dbTrash
    make

    #cd hg/htdocs
    #make doInstall destDir=$APACHDIR/htdocs FIND="find ."
    # dbTrash tool needed for trash cleaning
}

# redhat specific part of mysql and apache installation
function installRedhat () {
    echo2 
    echo2 Installing EPEL, ghostscript, libpng
    waitKey
    # make sure we have and EPEL and ghostscript
    yum -y install epel-release ghostscript

    # centos 7 and fedora 20 do not provide libpng by default
    if ldconfig -p | grep libpng12.so > /dev/null; then
        echo2 libpng12 found
    else
        yum -y install libpng12
    fi
    
    # install apache if not installed yet
    if [ ! -f /usr/sbin/httpd ]; then
        echo2
        echo2 Installing Apache and making it start on boot
        waitKey
        yum -y install httpd
        # start apache on boot
        chkconfig --level 2345 httpd on
        service httpd start
    else
        echo2 Apache already installed
    fi
    
    # download the apache config
    if [ ! -f $APACHECONF ]; then
        echo2
        echo2 Creating the Apache2 config file $APACHECONF
        waitKey
        downloadFile $APACHECONFURL > $APACHECONF
    fi
    service httpd restart

    # this triggers an error if rpmforge is not installed
    # but if rpmforge is installed, we need the option
    # psxy is not that important, we just skip it for now
    #yum -y install GMT hdf5 --disablerepo=rpmforge
    
    if [ -f /etc/init.d/iptables ]; then
       echo2 Opening port 80 for incoming connections to Apache
       waitKey
       iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
       iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
       service iptables save
       service iptables restart
    fi
    
    # MYSQL INSTALL ON REDHAT, quite involved, as MariaDB is increasingly the default

    # centos7 provides only a package called mariadb-server
    if yum list mysql-server 2> /dev/null ; then
        MYSQLPKG=mysql-server
    elif yum list mariadb-server 2> /dev/null ; then
        MYSQLPKG=mariadb-server
    else
        echo2 Cannot find a mysql-server package in the current yum repositories
        exit 100
    fi
    
    # even mariadb packages currently call their binary /usr/bin/mysqld_safe
    if [ ! -f /usr/bin/mysqld_safe ]; then
        echo2 
        echo2 Installing the Mysql or MariaDB server and make it start at boot.
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
        echo2 Mysql already installed
    fi
}

# OSX specific setup of the installation
function installOsx () 
{
   # check for xcode
   if [ -f /usr/bin/xcode-select 2> /dev/null > /dev/null ]; then
       echo2 Found XCode
   else
       echo2
       echo2 'This installer has to compile the UCSC tools locally on OSX.'
       echo2 'Please install XCode from https://developer.apple.com/xcode/downloads/'
       echo2 'Start XCode once and accept the Apple license.'
       echo2 'Then run this script again.'
       exit 101
   fi

   # make sure that the xcode command line tools are installed
   echo2 Checking/Installing Xcode Command line tools
   xcode-select --install 2> /dev/null >/dev/null  || true

   # in case that it is running, try to stop Apple's personal web server, we need access to port 80
   # ignore any error messages
   #if [ -f /usr/sbin/apachectl ]; then
       #echo2 Stopping the Apple Personal Web Server
       #/usr/sbin/apachectl stop 2> /dev/null || true
       #launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist 2> /dev/null || true
   #fi

   if [ -f ~root/.my.cnf ]; then
       echo2
       echo2 ~root/.my.cnf already exists. This will interfere with the installation.
       echo2 The file will be renamed to ~root/.my.cnf.old now.
       mv ~root/.my.cnf ~root/.my.cnf.old
       waitKey
   fi

   # get all external software like apache, mysql , openssl
   if [ ! -f $APACHEDIR/ext/src/allBuildOk.flag ]; then
       mkdir -p $APACHEDIR/ext/src
       cd $APACHEDIR/ext/src
       if [ "$BUILDEXT" == "1" ]; then
           buildApacheMysqlOpensslLibpng
       else
           echo2
           echo2 Downloading Apache/Mysql/OpenSSL/LibPNG binary build from UCSC
           cd $APACHEDIR
           downloadFile $BINPKGURL | tar xz
           mkdir -p $APACHEDIR/ext/src/
           touch $APACHEDIR/ext/src/allBuildOk.flag
           rm -f $APACHEDIR/ext/configOk.flag 
       fi

       # directory with .pid files has to be writeable
       chmod a+w $APACHEDIR/ext/logs
       # directory with .socket has to be writeable
       chmod a+w $APACHEDIR/ext

       touch $APACHEDIR/ext/src/allBuildOk.flag

   fi

   # configure apache and mysql 
   if [ ! -f $APACHEDIR/ext/configOk.flag ]; then
       cd $APACHEDIR/ext
       echo2 Creating mysql config in $APACHEDIR/ext/my.cnf
       echo '[mysqld]' > my.cnf
       echo "datadir = $APACHEDIR/mysqlData" >> my.cnf
       echo "default-storage-engine = myisam" >> my.cnf
       echo "default-tmp-storage-engine = myisam" >> my.cnf
       echo "skip-innodb" >> my.cnf
       echo "skip-networking" >> my.cnf
       echo "socket = $APACHEDIR/ext/mysql.socket" >> my.cnf
       echo '[client]' >> my.cnf
       echo "socket = $APACHEDIR/ext/mysql.socket" >> my.cnf

       # configure mysql
       #echo2 Creating Mysql system databases
       #mkdir -p $MYSQLDIR
       #scripts/mysql_install_db --datadir=$MYSQLDIR
       #SET_MYSQL_ROOT=1 # not needed with skip-networking
       cd $APACHEDIR
       # download minimal mysql db
       downloadFile $MYSQLDBURL | tar xz
       chown -R $MYSQLUSER:$MYSQLUSER $MYSQLDIR

       # configure apache
       echo2 Configuring Apache via files $APACHECONFDIR/httpd.conf and $APACHECONF
       downloadFile $APACHECONFURL > $APACHECONF
       # include browser config from apache config
       echo2 Appending browser config include line to $APACHECONFDIR/httpd.conf
       echo Include conf/001-browser.conf >> $APACHECONFDIR/httpd.conf
       # no need for document root, note BSD specific sed option -i
       # $SEDINPLACE 's/^DocumentRoot/#DocumentRoot/' $APACHECONFDIR/httpd.conf
       # server root provided on command line, note BSD sed -i option
       $SEDINPLACE 's/^ServerRoot/#ServerRoot/' $APACHECONFDIR/httpd.conf
       # need cgi and SSI - not needed anymore, are now compiled into apache
       # $SEDINPLACE 's/^#LoadModule include_module/LoadModule include_module/' $APACHECONFDIR/httpd.conf
       # $SEDINPLACE 's/^#LoadModule cgid_module/LoadModule cgid_module/' $APACHECONFDIR/httpd.conf
       # OSX has special username/group for apache
       $SEDINPLACE 's/^User .*$/User _www/' $APACHECONFDIR/httpd.conf
       $SEDINPLACE 's/^Group .*$/Group _www/' $APACHECONFDIR/httpd.conf
       # OSX is for development and OSX has a built-in apache so change port to 8080
       $SEDINPLACE 's/^Listen .*/Listen 8080/' $APACHECONFDIR/httpd.conf

       # to avoid the error message upon startup that htdocs does not exist
       mkdir -p /usr/local/apache/htdocs
        
       # create browserStartup.sh 
       echo2 Creating $APACHEDIR/browserStartup.sh

       downloadFile $STARTSCRIPTURL > $APACHEDIR/browserStartup.sh
       chmod a+x $APACHEDIR/browserStartup.sh

       # allowing any user to write to this directory, so any user can execute browserStartup.sh
       chmod -R a+w $APACHEDIR/ext
       # only mysql does not tolerate world-writable conf files
       chmod a-w $APACHEDIR/ext/my.cnf

       # development machine + mysql only reachable from localhost = empty root pwd
       # secureMysql - not needed
       touch $APACHEDIR/ext/configOk.flag 
   fi

   echo2 Running $APACHEDIR/browserStartup.sh to start mysql and apache
   $APACHEDIR/browserStartup.sh
   echo2 Waiting for mysql to start
   sleep 5
}

# function for Debian-specific installation of mysql and apache
function installDebian ()
{
    # update repos
    if [ ! -f /tmp/browserInstall.aptGetUpdateDone ]; then
       echo2 Running apt-get update
       apt-get update
       touch /tmp/browserInstall.aptGetUpdateDone
    fi

    # use dpkg to check if ghostscript is installed
    if dpkg-query -W ghostscript 2>&1 | grep "no packages found" > /dev/null; then 
        echo2
        echo2 Installing ghostscript
        waitKey
        apt-get --assume-yes install ghostscript
    fi

    if [ ! -f $APACHECONF ]; then
        echo2
        echo2 Now installing Apache2.
        echo2 "Apache's default config /etc/apache2/sites-enable/000-default will be"
        echo2 "deactivated. A new configuration $APACHECONF will be added and activated."
        echo2 The apache modules SSI and CGI and authz_core will be activated.
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
          echo2 Creating $APACHECONF
          downloadFile $APACHECONFURL > $APACHECONF
          a2ensite 001-browser
          a2dissite 000-default
          service apache2 restart
        fi
    fi

    if [[ ! -f /usr/sbin/mysqld ]]; then
        echo2
        echo2 Now installing the Mysql server. 
        echo2 The root password will be set to a random string and will be written
        echo2 to the file /root/.my.cnf so root does not have to provide a password on
        echo2 the command line.
        waitKey
        moveAwayMyCnf

        # do not prompt in apt-get, will set an empty mysql root password
        export DEBIAN_FRONTEND=noninteractive
        apt-get --assume-yes install mysql-server
        # flag so script will set mysql root password later to a random value
        SET_MYSQL_ROOT=1
    fi

}
# download apache mysql libpng openssl into the current dir
# and build them into $APACHEDIR/ext
function buildApacheMysqlOpensslLibpng () 
{
echo2
echo2 Now building cmake, openssl, pcre, apache and mysql into $APACHEDIR/ext
echo2 This can take up to 20 minutes on slower machines
waitKey
# cmake - required by mysql
# see http://mac-dev-env.patrickbougie.com/cmake/
echo2 Building cmake
curl --remote-name http://www.cmake.org/files/v3.1/cmake-3.1.3.tar.gz
tar -xzvf cmake-3.1.3.tar.gz
cd cmake-3.1.3
./bootstrap --prefix=$APACHEDIR/ext
make -j2
make install
cd ..
rm cmake-3.1.3.tar.gz

# see http://mac-dev-env.patrickbougie.com/openssl/  - required for apache
echo2 Building openssl
curl --remote-name https://www.openssl.org/source/openssl-1.0.2a.tar.gz
tar -xzvf openssl-1.0.2a.tar.gz
cd openssl-1.0.2a
./configure darwin64-x86_64-cc --prefix=$APACHEDIR/ext
# make -j2 aborted with an error
make
make install
cd ..
rm openssl-1.0.2a.tar.gz

# see http://mac-dev-env.patrickbougie.com/mysql/ 
echo2 Building mysql5.6
curl --remote-name --location https://dev.mysql.com/get/Downloads/MySQL-5.6/mysql-5.6.23.tar.gz
tar -xzvf mysql-5.6.23.tar.gz
cd mysql-5.6.23
../../bin/cmake \
  -DCMAKE_INSTALL_PREFIX=$APACHEDIR/ext \
  -DCMAKE_CXX_FLAGS="-stdlib=libstdc++" \
  -DMYSQL_UNIX_ADDR=$APACHEDIR/ext/mysql.socket \
  -DENABLED_LOCAL_INFILE=ON \
  -DWITHOUT_INNODB_STORAGE_ENGINE=1 \
  -DWITHOUT_FEDERATED_STORAGE_ENGINE=1 \
  .
make -j2
make install
cd ..
rm mysql-5.6.23.tar.gz

# pcre - required by apache
# see http://mac-dev-env.patrickbougie.com/pcre/
echo2 building pcre
curl --remote-name ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.36.tar.gz
tar -xzvf pcre-8.36.tar.gz
cd pcre-8.36
./configure --prefix=$APACHEDIR/ext --disable-shared --disable-cpp
make -j2
make install
cd ..
rm pcre-8.36.tar.gz

# apache2.4
# see http://mac-dev-env.patrickbougie.com/apache/
# and http://stackoverflow.com/questions/13587001/problems-with-compiling-apache2-on-mac-os-x-mountain-lion
# note that the -deps download of 2.4.12 does not include the APR, so we get it from the original source
curl http://apache.sunsite.ualberta.ca/httpd/httpd-2.4.12-deps.tar.gz | tar xz 
curl http://apache.sunsite.ualberta.ca/httpd/httpd-2.4.12.tar.gz | tar xz 
cd httpd-2.4.12

# build APR
cd srclib/
cd apr; configure --prefix=$APACHEDIR/ext; make -j2; make install; cd ..
cd apr-util; configure --prefix=$APACHEDIR/ext --with-apr=$APACHEDIR/ext/bin/apr-1-config; make -j2; make install; cd ..
cd ..

# now compile, compile SSL statically so there is no confusion with Apple's SSL
# also include expat, otherwise Apple's expat conflicts
./configure --prefix=$APACHEDIR/ext --enable-ssl --with-ssl=$APACHEDIR/ext --enable-ssl-staticlib-deps  --enable-mods-static=ssl --with-expat=builtin --with-pcre=$APACHEDIR/ext/bin/pcre-config --enable-pcre=static --disable-shared --with-apr=$APACHEDIR/ext/bin/apr-1-config --with-apr-util=$APACHEDIR/ext/bin/apu-1-config --enable-modules="all ssl cache"

make -j2
make install
cd ..

# libpng - required for the genome browser
curl --remote-name --location  'http://downloads.sourceforge.net/project/libpng/libpng16/1.6.16/libpng-1.6.16.tar.gz'
tar xvfz libpng-1.6.16.tar.gz 
cd libpng-1.6.16/
./configure --prefix=$APACHEDIR/ext
make -j2
make install
cd ..
rm libpng-1.6.16.tar.gz

}

function mysqlChangeRootPwd ()
{
   # first check if an old password still exists in .my.cnf
   if [ -f ~root/.my.cnf ]; then
       echo2 ~root/.my.cnf already exists, you might want to remove this file
       echo2 and restart the script if an error message appears below.
       echo2
   fi

   # generate a random char string
   # OSX's tr is quite picky with unicode, so change LC_ALL temporarily
   MYSQLROOTPWD=`cat /dev/urandom | LC_ALL=C tr -dc A-Z-a-z-0-9 | head -c8` || true
   # paranoia check
   if [[ "$MYSQLROOTPWD" == "" ]]; then
       echo2 Error: could not generate a random Mysql root password
       exit 111
   fi

   echo2
   echo2 The Mysql server was installed and therefore has an empty root password.
   echo2 Trying to set mysql root password to the randomly generated string '"'$MYSQLROOTPWD'"'

   # now set the mysql root password
   if $MYSQLADMIN -u root password $MYSQLROOTPWD; then
       # and write it to my.cnf
       if [ ! -f ~root/.my.cnf ]; then
           echo2
           echo2 Writing password to ~root/.my.cnf so root does not have to provide a password on the 
           echo2 command line.
           echo '[client]' >> ~root/.my.cnf
           echo user=root >> ~root/.my.cnf
           echo password=${MYSQLROOTPWD} >> ~root/.my.cnf
           chmod 600 ~root/.my.cnf
           waitKey
        else
           echo2 ~root/.my.cnf already exists, not changing it.
        fi 
   else
       echo2 Could not connect to mysql to set the root password to $MYSQLROOTPWD.
       echo2 A root password must have been set by a previous installation.
       echo2 Please reset the root password to an empty password by following these
       echo2 instructions: http://dev.mysql.com/doc/refman/5.0/en/resetting-permissions.html
       echo2 Then restart the script.
       echo2 Or, if you remember the old root password, write it to a file ~root/.my.cnf, 
       echo2 create three lines
       echo2 '[client]'
       echo2 user=root
       echo2 password=PASSWORD
       echo2 run chmod 600 ~root/.my.cnf and restart this script.
       exit 123
   fi
}

function checkCanConnectMysql ()
{
if $MYSQL -e "SHOW DATABASES;" 2> /dev/null > /dev/null; then
    true
else
    echo2 "ERROR:"
    echo2 "Cannot connect to mysql database server, a root password has probably been setup before."
    # create a little basic .my.cnf for the current root user
    # so the mysql root password setup is easier
    if [ ! -f ~root/.my.cnf ]; then
       echo '[client]' >> ~root/.my.cnf
       echo user=root >> ~root/.my.cnf
       echo password=YOURMYSQLPASSWORD >> ~root/.my.cnf
       chmod 600 ~root/.my.cnf
       echo2
       echo2 A file ${HOME}/.my.cnf was created with default values
       echo2 Edit the file ${HOME}/.my.cnf and replace YOURMYSQLPASSWORD with the mysql root password that you
       echo2 defined during the mysql installation.
    else
       echo2
       echo2 A file ${HOME}/.my.cnf already exists
       echo2 Edit the file ${HOME}/.my.cnf and make sure there is a '[client]' section
       echo2 and under it at least two lines with 'user=root' and 'password=YOURMYSQLPASSWORD'.
    fi
       
    echo2 "Then run this script again."
    exit 200
fi
   
# DETECT AND DEACTIVATE SELINUX
if [ -f /sbin/selinuxenabled ]; then
    if /sbin/selinuxenabled; then
       echo2
       echo2 The Genome Browser requires that SELINUX is deactivated.
       echo2 Deactivating it now.
       waitKey
       # deactivate selines until next reboot
       setenforce 0
       # permanently deactivate after next reboot
       sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux
    fi
fi

}

# setup the mysql databases for the genome browser and grant 
# user access rights
function mysqlDbSetup ()
{
    # -------------------
    # Mysql db setup
    # -------------------
    echo2
    echo2 Creating Mysql databases customTrash, hgTemp and hgcentral
    waitKey
    $MYSQL -e 'CREATE DATABASE IF NOT EXISTS customTrash;'
    $MYSQL -e 'CREATE DATABASE IF NOT EXISTS hgcentral;'
    $MYSQL -e 'CREATE DATABASE IF NOT EXISTS hgTemp;'
    $MYSQL -e 'CREATE DATABASE IF NOT EXISTS hgFixed;' # empty db needed for gencode tracks
    downloadFile http://$HGDOWNLOAD/admin/hgcentral.sql | $MYSQL hgcentral
    # the blat servers don't have fully qualified dom names in the download data
    $MYSQL hgcentral -e 'UPDATE blatServers SET host=CONCAT(host,".cse.ucsc.edu");'
    
    echo2
    echo2 "Will now grant permissions to browser database access users:"
    echo2 "User: 'browser', password: 'genome' - full database access permissions"
    echo2 "User: 'readonly', password: 'access' - read only access for CGI binaries"
    echo2 "User: 'readwrite', password: 'update' - readwrite access for hgcentral DB"
    waitKey
    
    #  Full access to all databases for the user 'browser'
    #       This would be for browser developers that need read/write access
    #       to all database tables.  
    $MYSQL -e "GRANT SELECT, INSERT, UPDATE, DELETE, FILE, "\
"CREATE, DROP, ALTER, CREATE TEMPORARY TABLES on *.* TO browser@localhost "\
"IDENTIFIED BY 'genome';"
    
    # FILE permission for this user to all databases to allow DB table loading with
    #       statements such as: "LOAD DATA INFILE file.tab"
    # For security details please read:
    #       http://dev.mysql.com/doc/refman/5.1/en/load-data.html
    #       http://dev.mysql.com/doc/refman/5.1/en/load-data-local.html
    $MYSQL -e "GRANT FILE on *.* TO browser@localhost IDENTIFIED BY 'genome';" 
    
    #   Read only access to genome databases for the browser CGI binaries
    $MYSQL -e "GRANT SELECT, CREATE TEMPORARY TABLES on "\
"*.* TO readonly@localhost IDENTIFIED BY 'access';"
    $MYSQL -e "GRANT SELECT, INSERT, CREATE TEMPORARY TABLES on hgTemp.* TO "\
"readonly@localhost IDENTIFIED BY 'access';"
    
    # Readwrite access to hgcentral for browser CGI binaries to keep session state
    $MYSQL -e "GRANT SELECT, INSERT, UPDATE, "\
"DELETE, CREATE, DROP, ALTER on hgcentral.* TO readwrite@localhost "\
"IDENTIFIED BY 'update';"
    
    # create /gbdb and let the apache user write to it
    # hgConvert will download missing liftOver files on the fly and needs write
    # write access
    mkdir -p $GBDBDIR
    chown $APACHEUSER:$APACHEUSER $GBDBDIR
    
    # the custom track database needs it own user and permissions
    $MYSQL -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,ALTER,INDEX "\
"on customTrash.* TO ctdbuser@localhost IDENTIFIED by 'ctdbpassword';"
    
    # by default hgGateway needs an empty hg19 database, will crash otherwise
    $MYSQL -e 'CREATE DATABASE IF NOT EXISTS hg19'
    # mm9 needs an empty hg18 database
    $MYSQL -e 'CREATE DATABASE IF NOT EXISTS hg18'
    
    $MYSQL -e "FLUSH PRIVILEGES;"
    
}
# --- end of functions --- 

# -- START OF SCRIPT  --- MAIN ---

if [[ "$EUID" != "0" ]]; then
  echo "This script must be run as root or with sudo like this:"
  echo "sudo -H $0"
  exit 1
fi

# On Debian and OSX, sudo by default does not update the HOME variable (hence the -H option above)
if [[ "${SUDO_USER:-}" != "" ]]; then
   export HOME=~root
fi

trap errorHandler ERR

# OPTION PARSING

while getopts ":baut:hof" opt; do
  case $opt in
    h)
      cat <<EOF
$0 [options] [assemblyList] - UCSC genome browser install script

parameters:
  no parameter       - setup Apache and Mysql, do not download any assembly
  <assemblyList>     - download Mysql + /gbdb files for a space-separated
                       list of genomes

examples:
  bash $0             - install Genome Browser, do not download any genome
                        assembly switch to on-the-fly mode (see the -f option)
  bash $0 hg19 mm9    - install Genome Browser, download hg19 and mm9, switch
                        to offline mode (see the -o option)
  bash $0 -t noEncode hg19  - install Genome Browser, download hg19 but no
                              ENCODE tables switch to offline mode (see the -o
                              option)

All options have to precede the list of genome assemblies.

options:
  -a   - use alternative download server at SDSC
  -b   - batch mode, do not prompt for key presses
  -t   - download track selection, requires a value.
         Download only certain tracks, possible values:
         noEncode = do not download any tables with the wgEncode prefix, 
                    except Gencode genes, saves 4TB/6TB for hg19
         bestEncode = our ENCODE recommendation, all summary tracks, saves
                      2TB/6TB for hg19
         minimal = only RefSeq/Gencode genes and SNPs, 5GB for hg19
  -u   - use UDR (fast UDP) file transfers for the download.
         Requires at least one open UDP incoming port 9000-9100.
         (UDR is not available for Mac OSX)
  -o   - switch to offline-mode. Remove all statements from hg.conf that allow
         loading data on-the-fly from the UCSC download server. Requires that
         you have downloaded at least one assembly. Default if at least one
         assembly has been specified.
  -f   - switch to on-the-fly mode. Change hg.conf to allow loading data
         through the internet, if it is not available locally. The default mode
         unless an assembly has been provided during install
  -h   - this help message
EOF
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
    t)
      val=${OPTARG}
      if [[ "$val" == "bestEncode" ]]; then
          RSYNCOPTS="-m --include=wgEncodeGencode* --include=wgEncodeBroadHistone* --include=wgEncodeReg* --include=wgEncodeAwg* --include=wgEncode*Mapability* --include=*/ --exclude=wgEncode*"
          ONLYGENOMES=0
      elif [[ "$val" == "noEncode" ]]; then
          RSYNCOPTS="-m --include=wgEncodeGencode* --include */ --exclude=wgEncode*"
          ONLYGENOMES=0
      elif [[ "$val" == "minimal" ]]; then
          # gbCdnaInfo
          RSYNCOPTS="-m --include=grp.* --include=gold.* --include=chromInfo.* --include=trackDb* --include=hgFindSpec.* --include=gap.* --include=*.2bit --include=html/description.html --include=refGene* --include=refLink.* --include=wgEncodeGencode*V19* --include snp142Common.* --include rmsk* --include */ --exclude=*"
          ONLYGENOMES=1 # do not download hgFixed,go,proteome etc
      else
          echo "Unrecognized -t value. Please read the help message, by running bash $0 -h"
          exit 1
      fi
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
    APACHECONFDIR=$APACHEDIR/ext/conf # only used by the OSX-spec part
    APACHECONF=$APACHECONFDIR/001-browser.conf
    APACHEUSER=_www # predefined by Apple
    MYSQLDIR=$APACHEDIR/mysqlData
    MYSQLUSER=_mysql # predefined by Apple
    MYSQL="$APACHEDIR/ext/bin/mysql --socket=$APACHEDIR/ext/mysql.socket"
    MYSQLADMIN="$APACHEDIR/ext/bin/mysqladmin --socket=$APACHEDIR/ext/mysql.socket"
    SEDINPLACE="sed -Ei .bak" # difference BSD vs Linux

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

# -----  OS - SPECIFIC part -----
if [ ! -f $COMPLETEFLAG ]; then
   if [[ "$DIST" == "OSX" ]]; then
      installOsx
   elif [[ "$DIST" == "debian" ]]; then
      installDebian
   elif [[ "$DIST" == "redhat" ]]; then
      installRedhat
   fi
fi
# OS-specific mysql/apache installers can SET_MYSQL_ROOT to 1 to request that the root
# mysql user password be changed

# ---- END OS-SPECIFIC part -----

if [[ "${SET_MYSQL_ROOT}" == "1" ]]; then
   mysqlChangeRootPwd
fi

# before we do anything else with mysql
# we need to check if we can access it. 
# so test if we can connect to the mysql server
# need to temporarily deactivate error abort mode, in case mysql cannot connect

checkCanConnectMysql

# Download over own statically compiled udr binary
if [[ ! -f /usr/local/bin/udr && "$RSYNC" = *udr* ]]; then
  echo2 'Downloading download-tool udr (UDP-based rsync with multiple streams) to /usr/local/bin/udr'
  waitKey
  downloadFile $UDRURL > /usr/local/bin/udr
  chmod a+x /usr/local/bin/udr
fi

# CGI DOWNLOAD AND HGCENTRAL MYSQL DB SETUP

if [ ! -f $COMPLETEFLAG ]; then
    # test if an apache file is already present
    if [ -f "$APACHEDIR" ]; then
        echo2 error: please remove the file $APACHEDIR, then restart the script with "bash $0".
        exit 249
    fi

    # check if /usr/local/apache is empty
    # on OSX, we had to create an empty htdocs, so skip this check there
    if [ -d "$APACHEDIR" -a "$OS" != "OSX" ]; then
        echo2 error: the directory $APACHEDIR already exists.
        echo2 This installer has to overwrite it, so please move it to a different name
        echo2 or remove it. Then start the installer again with "bash $0"
        exit 250
    fi

    mysqlDbSetup

    # -------------------
    # CGI installation
    # -------------------
    echo2
    echo2 Creating $APACHEDIR/cgi-bin and $APACHEDIR/htdocs and downloading contents from UCSC
    waitKey
    
    # create apache directories: HTML files, CGIs, temporary and custom track files
    mkdir -p $APACHEDIR/htdocs $APACHEDIR/cgi-bin $APACHEDIR/trash $APACHEDIR/trash/customTrash
    
    # the CGIs create links to images in /trash which need to be accessible from htdocs
    cd $APACHEDIR/htdocs 
    ln -fs ../trash
    
    # download the sample hg.conf into the cgi-bin directory
    echo2 Downloading Genome Browser config file $APACHEDIR/cgi-bin/hg.conf
    downloadFile $HGCONFURL > $APACHEDIR/cgi-bin/hg.conf
    
    # hg.conf tweaks
    # redhat distros have the same default socket location set in mysql as
    # in our binaries. To allow mysql to connect, we have to remove the socket path.
    # Also change the psxy path to the correct path for redhat, /usr/bin/
    if [ "$DIST" == "redhat" ]; then
       echo2 Adapting mysql socket locations in $APACHEDIR/cgi-bin/hg.conf
       sed -i "/socket=/s/^/#/" $APACHEDIR/cgi-bin/hg.conf
       sed -i "/^hgc\./s/.usr.lib.gmt.bin/\/usr\/bin/" $APACHEDIR/cgi-bin/hg.conf
    elif [ "$DIST" == "OSX" ]; then
       # in OSX adapt the sockets
       # note that the sed -i syntax is different from linux
       echo2 Adapting mysql socket locations in $APACHEDIR/cgi-bin/hg.conf
       sockFile=$APACHEDIR/ext/mysql.socket
       $SEDINPLACE "s|^#?socket=.*|socket=$sockFile|" $APACHEDIR/cgi-bin/hg.conf
       $SEDINPLACE "s|^#?customTracks.socket.*|customTracks.socket=$sockFile|" $APACHEDIR/cgi-bin/hg.conf
       $SEDINPLACE "s|^#?db.socket.*|db.socket=$sockFile|" $APACHEDIR/cgi-bin/hg.conf
       $SEDINPLACE "s|^#?central.socket.*|central.socket=$sockFile|" $APACHEDIR/cgi-bin/hg.conf
    fi
    
    # download the CGIs
    if [[ "$OS" == "OSX" ]]; then
        setupCgiOsx
    else
        # don't download RNAplot, it's a 32bit binary that won't work
        # this means that hgGene cannot show RNA structures but that's not a big issue
        $RSYNC -avzP --exclude RNAplot $HGDOWNLOAD::cgi-bin/ $APACHEDIR/cgi-bin/
    fi
        
    # download the html docs
    $RSYNC -avzP $HGDOWNLOAD::htdocs/ $APACHEDIR/htdocs/ 
    
    # assign all files just downloaded to a valid user. 
    # This also allows apache to write into the trash dir
    chown -R $APACHEUSER:$APACHEUSER $APACHEDIR/cgi-bin $APACHEDIR/htdocs $APACHEDIR/trash
    
    touch $COMPLETEFLAG

    # if there is not genome to download, stop here
    if [ "${1:-}" == "" ]; then
       echo2
       echo2 Install complete. You should now be able to point your web browser to this machine
       echo2 and use your UCSC Genome Browser mirror.
       echo2
       echo2 Notice that this mirror is still configured to use Mysql and data files loaded
       echo2 through the internet from UCSC. From most locations on the world, this is very slow.
       echo2 It also requires an open outgoing TCP port 3306 for Mysql to genome-mysql.cse.ucsc.edu
       echo2 and open TCP port 80 to hgdownload.soe.ucsc.edu.
       echo2
       echo2 To speed up the installation, you need to download genome data to the local
       echo2 disk. To download a genome assembly and all its files now, call this script again with
       echo2 the parameters '"<assemblyName1> <assemblyName2> ..."', e.g. '"'bash $0 mm10 hg19'"'
       echo2 
       showMyAddress
       exit 0
    fi
    
fi

# GENOME DOWNLOAD

DBS=${*:1}

if [[ "$DBS" == "" ]]; then
   echo2
   echo2 The browser seems to be installed on this machine already, the file $COMPLETEFLAG exists.
   echo2
   echo2 If you have not downloaded any genome assemblies yet, data is loaded from UCSC,
   echo2 which is very slow and requires outgoing TCP port 3306 to be open.
   echo2
   echo2 To download data files to your own machine, call this script with a list of genome assemblies, e.g. 
   echo2   bash $0 cb1 ce6
   echo2
   echo2 Run '"'bash $0'"' -h to get more information on options.
   echo2 
   exit 125
fi

echo2
echo2 Downloading databases $DBS plus hgFixed/proteome/go from the UCSC download server
echo2
echo2 Determining download file size... please wait...

if [ "ONLYGENOMES" == "0" ]; then
    MYSQLDBS="$DBS proteome uniProt go hgFixed"
else
    MYSQLDBS="$DBS"
fi

# rsync is doing globbing itself, so switch it off temporarily
set -f
# use rsync to get total size of files in directories and sum the numbers up with awk
for db in $MYSQLDBS; do
    rsync -avn $HGDOWNLOAD::mysql/$db/ $MYSQLDIR/$db/ $RSYNCOPTS | grep ^'total size' | cut -d' ' -f4 | tr -d ', ' 
done | awk '{ sum += $1 } END { print "| Required space in '$MYSQLDIR':", sum/1000000000, "GB" }'

for db in $DBS; do
    rsync -avn $HGDOWNLOAD::gbdb/$db/ $GBDBDIR/$db/ $RSYNCOPTS | grep ^'total size' | cut -d' ' -f4 | tr -d ','
done | awk '{ sum += $1 } END { print "| Required space in '$GBDBDIR':", sum/1000000000, "GB" }'

echo2
echo2 Currently available disk space on this system:
echo2
df -h  | awk '{print "| "$0}'
echo2 
echo2 If your current disk space is not sufficient, you can mount
echo2 'network storage servers (e.g. NFS) or add cloud provider storage'
echo2 '(e.g. Openstack Cinder Volumes, Amazon EBS, Azure Storage)'
echo2
echo2 Move the current data in $GBDBDIR and $MYSQLDIR onto these volumes and
echo2 symlink $GBDBDIR and $MYSQLDIR to the new locations. You might have to stop 
echo2 Mysql temporarily to do this.
echo2
echo2 You can interrupt this script with CTRL-C now, add more space and rerun the 
echo2 script later with the same parameters.
echo2
waitKey

# now do the actual download of mysql files
for db in $MYSQLDBS; do
   echo2 Downloading Mysql files for mysql database $db
   $RSYNC --progress -avzp $RSYNCOPTS $HGDOWNLOAD::mysql/$db/ $MYSQLDIR/$db/ 
   chown -R $MYSQLUSER:$MYSQLUSER $MYSQLDIR/$db
done

# download /gbdb files
for db in $DBS; do
   echo2 Downloading $GBDBDIR files for assembly $db
   mkdir -p $GBDBDIR
   $RSYNC --progress -avzp $RSYNCOPTS $HGDOWNLOAD::gbdb/$db/ $GBDBDIR/$db/
   chown -R $APACHEUSER:$APACHEUSER $GBDBDIR/$db
done

set +f

goOffline # modify hg.conf and remove all statements that use the UCSC download server

echo2
echo2 Install complete. You should now be able to point your web browser to this machine
echo2 and use your UCSC Genome Browser mirror.
echo2

showMyAddress

echo2 
echo2 Note that the installation assumes that emails cannot be sent from
echo2 this machine. New Genome Browser user accounts will not receive confirmation emails.
echo2 To change this, edit the file $APACHEDIR/cgi-bin/hg.conf and modify the settings
echo2 'that start with "login.", mainly "login.mailReturnAddr"'.
echo2
echo2 Please send any other questions to the mailing list, genome-mirror@soe.ucsc.edu .
waitKey
