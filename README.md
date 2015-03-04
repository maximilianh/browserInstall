# An install script for the UCSC Genome Browser

This script installs mysql, apache, ghostscript, configures them and copies the UCSC Genome
Browser CGIs onto the local machine under /usr/local/apache/. At the end it shows instructions
how to download genome assemblies to the local machine. 

The script has been tested with Ubuntu 14 LTS, Centos 6, Centos 7 and Fedora 20.

Run this script as root, preferably on a recently installed machine, which is what we tested.

    su
    wget https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserInstall.sh
    bash browserInstall.sh
