# API Security Scripts

I was tediously installing and uninstalling the tools and docker images for the APISec University course after every new start I wanted to make or reinstall of Kali. To make this a little easier I created scripts to do most of the work for me.

## apisec_tool_install.sh

This script installs all of the applications for the course. Although you will still need to configure the firefox proxy, add the extensions to Burp and update zaproxy. 

## manage_docker_builds.sh

This is an updated script for multiple hacking docker images. I wanted to have more than just the APISec University images to play with. 

crapi - completely ridiculous API : Port 8888  
vapi - Vulnerable Adversely Programmed Interface : Port 80  
dvga - Damn Vulnerable GraphQL Application : Port 5013  
juice-shop - OWASP Juice Shop : Port 3000  

This script will ***install, update, start, stop, clean*** any of these docker images. You also have the ability to allow external visibility on the docker containers. vAPI and Juice Shop and exteernally accessible by default. The script also allows for configuring dvga and crapi for external connectivity. <span style="color:red">(Warning: Probably best not to use this on an internet facing server.)</span>

## manage_crapi_vapi_builds.sh

To help manage the docker installs this script can do the following options

***This script is best used in an environment where other docker images do not exist. Running clean may remove unused images and volumes for any docker application installed.***


To run this script do the following:  
&nbsp;&nbsp;&nbsp;&nbsp;chmod +x manage_crapi_vapi_builds.sh  
&nbsp;&nbsp;&nbsp;&nbsp;./manage_crapi_vapi_builds.sh \<option\>

**install** - Installs both crAPI and vapi docker images and starts them.  
**start** - To start the docker images if they are not running.  
**stop** - Stops all docker images.  
**restart** - Stops and starts the docker images.  
**clean** - Will wipe everything to do with the docker images.  

When running the script you will be asked if you want to access this server externally. If you are running these on an external server and not your local system answer "y" otherwise is you are installing on a local maching answer "n".

