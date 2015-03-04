# An install script for the UCSC Genome Browser

This script installs mysql, apache, ghostscript, configures them and copies the UCSC Genome
Browser CGIs onto the local machine under /usr/local/apache/. At the end it shows instructions
how to download genome assemblies to the local machine. 

The script has been tested with Ubuntu 14 LTS, Centos 6, Centos 7 and Fedora 20.

Run this script as root, preferably on a freshly installed machine, which is what we tested.

    su
    wget https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserInstall.sh
    bash browserInstall.sh

If your linux distribution is not supported, you can file pull requests, open an issue here
or contact genome-mirror@soe.ucsc.edu. 
More installation instructions are at http://genome-source.cse.ucsc.edu/gitweb/?p=kent.git;a=tree;f=src/product
