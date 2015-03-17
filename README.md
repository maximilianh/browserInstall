# An install script for the UCSC Genome Browser

This script installs mysql, apache, ghostscript, configures them and copies the UCSC Genome
Browser CGIs onto the local machine under /usr/local/apache/. At the end it shows instructions
how to download genome assemblies to the local machine. 

The script has been tested with Ubuntu 14 LTS, Centos 6, Centos 7, Fedora 20 and OSX 10.10.

Run this script as root like this:

    sudo -i
    wget https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserInstall.sh
    bash browserInstall.sh

On OSX, use curl:

    sudo -i
    curl https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserInstall.sh > browserInstall.sh
    bash browserInstall.sh

The script goes through three steps:

1. Mysql and Apache are installed and setup with the right package manager (yum or apt-get or port). A default random password is set for the Mysql root user and added to the ~/.my.cnf file of the Unix root account. 
    1. If you already have setup Mysql, you would need to create to create the file ~/.my.cnf, the script will detect this and create a template file for you.
2. The script then downloads the CGIs and sets up the central Mysql database. It
stops and asks you to try out the installation from your internet browser.
3. You can run the script with a list genome assemblies (e.g. bash browserInstall.sh hg19).
if you want to install a complete genome assembly on your local machine. Rsync is used for this download. 
    1. Alternatively you can use UDR a UDP-based fast transfer protocol (bash browserInstall.sh -u hg19). Call the script with -h to get a list of the parameters (bash browserInstall.sh -h). 

When you want to update an existing installation, you can call the script with the "update" parameter like this: "bash browserInstall.sh update".

The script also does many small things, like placing the symlinks, detecting mariadb, deactivating SELinux, finding the right path for your apache install and adapting the Mysql socket config.

If you find a bug or your linux distribution is not supported, please file pull requests or open an issue here or email me. For other installation problems, you can contact genome-mirror@soe.ucsc.edu. 
More details about the Genome Browser installation are at http://genome-source.cse.ucsc.edu/gitweb/?p=kent.git;a=tree;f=src/product
