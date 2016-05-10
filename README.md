# An install script for the UCSC Genome Browser

This script installs mysql, apache, ghostscript, configures them and copies the UCSC Genome
Browser CGIs onto the local machine under /usr/local/apache/. At the end it shows instructions
how to download genome assemblies to the local machine. 

The script has been tested with Ubuntu 14 LTS, Centos 6, Centos 6.7, Centos 7, Fedora 20 and OSX 10.10.

It has also been tested on virtual machines in Amazon EC2 (Centos 6 and Ubuntu
14) and Microsoft Azure (Ubuntu). If you do not want to download the full genome assembly,
you need to select the data centers called "San Francisco" (Amazon) or "West
Coast" (Microsoft) for best performance. Other data centers (e.g. East Coast) will require a local
copy of the genome assembly, which can mean 2TB-6TB of storage for the hg19 assembly. Note that this
exceeds the current maximum size of a single Amazon EBS volume.

Run this script as root like this:

    sudo -i
    wget https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserSetup.sh
    bash browserSetup.sh install

If you do not have wget installed, use curl instead:

    sudo -i
    curl https://raw.githubusercontent.com/maximilianh/browserInstall/master/browserSetup.sh > browserSetup.sh
    bash browserSetup.sh install

The installation goes through three steps:

1. Mysql and Apache are installed and setup with the right package manager (yum or apt-get or port). A default random password is set for the Mysql root user and added to the ~/.my.cnf file of the Unix root account. 
    1. If you already have setup Mysql, you would need to create to create the file ~/.my.cnf, the script will detect this and create a template file for you.
2. The script then downloads the CGIs and sets up the central Mysql database. It
stops and asks you to try out the installation from your internet browser.
3. You can also download a completely genome assembly on your local machine. Run or re-run the script with the list of assemblies (e.g. bash browserInstall.sh hg19). By default rsync is used for the download.
    1. Alternatively you can use UDR a UDP-based fast transfer protocol (bash browserInstall.sh -u hg19). Call the script with -h to get a list of the other parameters (bash browserInstall.sh -h). 

When you want to update an existing installation, you can call the script with the "update" parameter like this: "bash browserInstall.sh update".

The script also does many small things, like placing the symlinks, detecting mariadb, deactivating SELinux, finding the right path for your apache install and adapting the Mysql socket config.

If you find a bug or your linux distribution is not supported, please file pull requests or open an issue here or email me. For other installation problems, you can contact genome-mirror@soe.ucsc.edu. 
More details about the Genome Browser installation are at http://genome-source.cse.ucsc.edu/gitweb/?p=kent.git;a=tree;f=src/product

Thanks to Daniel Vera (bio.fsu.edu) for his RHEL install notes.
