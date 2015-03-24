#!/bin/bash
# file to start environment necessary for the genome browser, currently only used on OSX:
# starts mysql and apache
# with parameter "-e" modifies PATH and restarts a login shell
set -e

APACHEDIR=/usr/local/apache
BASEDIR=$APACHEDIR/ext

# kill and start mysql
if [ -f $BASEDIR/logs/mysql.pid ]; then
   kill `cat $BASEDIR/logs/mysql.pid`
   sleep 3
fi
if [ -f $BASEDIR/bin/mysqld_safe ]; then
    $BASEDIR/bin/mysqld_safe --defaults-file=$BASEDIR/my.cnf --user=_mysql --pid-file=$BASEDIR/logs/mysql.pid &
fi

# kill and start apache
if [ -f "$BASEDIR/logs/httpd.pid" ]; then
   kill `cat $BASEDIR/logs/httpd.pid`
fi
if [ -f $BASEDIR/bin/httpd ]; then
   $BASEDIR/bin/httpd -d "$BASEDIR"
fi

if [[ "$1" == "-e" ]]; then
    export PATH="$BASEDIR/bin:$PATH"
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

    # find parent process name of this process and spawn new shell if it's bash or tcsh
    parent=`ps -p $PPID -o comm=`
    
    if [[ "$parent" == "tcsh" ]]; then
       echo Adapting PATH and starting new tcsh
       tcsh
    elif [[ "$parent" == "bash" ]]; then
       echo Adapting PATH and starting new bash
       bash -l
    else
       echo Not changing PATH, parent is not bash or tcsh
    fi
fi

