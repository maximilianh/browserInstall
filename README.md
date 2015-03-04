# An install script for the UCSC Genome Browser

This script installs mysql, apache, ghostscript, configures them and copies the UCSC Genome
Browser CGIs onto the local machine under /usr/local/apache/. At the end it shows instructions
how to download genome assemblies to the local machine. 

The script has been tested with Ubuntu 14 LTS, Centos 6, Centos 7 and Fedora 20.

Run this script as root like this:

    su
    wget https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserInstall.sh
    bash browserInstall.sh

The script goes through three steps:

1. Mysql and Apache are installed and setup with the right package manager (yum or apt-get). The package manager will ask you define a password for Mysql. The script then stops and asks you to add your mysql root user credentials to /root/.my.cnf and re-run the script with the "download" parameter.
2. The script then downloads the CGIs and sets up the central Mysql database. It
then stops and asks you to try out the installation from your internet browser
3. You can rerun the script with the "get <database>" (e.g. "get hg19") parameter
if you want to install a complete genome assembly on your local machine. Rsync is used for this download.

When you want to update an existing installation, you can call the script with the "update" parameter like this: "bash browserInstall.sh update".

If you find a bug or your linux distribution is not supported, please file pull requests or open an issue here or email me. For other installation problems, you can contact genome-mirror@soe.ucsc.edu. 
More details about the Genome Browser installation are at http://genome-source.cse.ucsc.edu/gitweb/?p=kent.git;a=tree;f=src/product
