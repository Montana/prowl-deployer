![deployer](http://www.getprowl.com/images/deployer.png)

## Prowl Deployer

A Smart command line tool to deploy/maintain small Django applications easily through VPS instances. Prowl Deployer is useful for EC2 and DigitalOcean instances that you want to quickstart.

### Usage

Pick the image of your choice, in this instance we are using DigitalOcean (we use this at Prowl), and we are using the Ubuntu image

<pre>sudo apt-get install python && pip</pre>

### Setup

Once the Prowl deployer is installed you must setup the basic configuration. In the example below I create a user called Prowl

   <pre>prowldeployer setup --supervisor-user prowl --deployer-home /home/prowl --install all</pre>

This command will install all needed dependicies to get Deployer up & running. It will configure nginx and supervisord to be running at as soon as you start the VPS. Also will create a sudoers file to give permissions to the specific users

   <pre>prowldeployer server --ssh set</pre>

This command will create a brand new SSH instance. It's the same as running ssh-keygen -t rsa. You MUST run this command with the user you set the system up with, in this example we used Prowl

### Django Setup

To start the Django project in the VPS 

   <pre>prowldeployer project --name todolist --git https://github.com/Montana/prowldeployer --site-addr "http://www.github.com/Montana/prowldeployer" --install</pre>

This is essentially the main goal of this tool. You must set a project name (--name), a git repo (--git) and a site(s) address(es) (--site-addr) that the app/site must bind to. Some of the dependencies that you'll need are the following 

<pre>requirements.pip
south
</pre>

### Questions?

Email me at montana@getprowl.com Written by Montana Mendy.
