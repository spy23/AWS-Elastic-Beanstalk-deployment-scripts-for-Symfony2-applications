AWS-Elastic-Beanstalk-deployment-scripts-for-Symfony2-applications
==================================================================

1. **Get the lastest eb AMI:** 
First you'll need to start a fresh elastic beanstalk environment. You can simply deploy the sample application. Than follow the steps to 7. described in this guide: [Using Custom AMIs](http://docs.amazonwebservices.com/elasticbeanstalk/latest/dg/using-features.customami.html)
You'll end up with a running EC2 instance with all the configuration you need to use it as an eb image.

2. **Connect to your EC2 instance:** Switch to the root user:

    $ sudo -i

3. **Customize the php.ini:** 

    $ vi /etc/php.ini

I've added a pdf extension, set data.timezone and disabled 
`short_open_tags`. You can do whatever you need to do.

4. **Customize phpapplication.rb:** 
This is the deployment script. It will be executed every time you deploy a new application version. It is the Holy Grail for your symfony cli commands.
You can use my script as a basis for your work:

[AWS-Elastic-Beanstalk-deployment-scripts-for-Symfony2-applications](https://github.com/spy23/AWS-Elastic-Beanstalk-deployment-scripts-for-Symfony2-applications)

I appreciate your feedback. Feed free to fork the repository and push your modifications. The current script is for Symfony 2.0.x. I bet you'll have to modify it, to make it work with Symfony 2.1.x (Composer) 

5. **Clean up your cli history:**

    $ rm -f ~/.bash_history; history -c;
    $ exit;
    $ rm -f ~/.bash_history; history -c;
    $ exit;

6. **Your custom AMI is ready.** 
Continue with step 7. from the AMI guide: [Using Custom AMIs](http://docs.amazonwebservices.com/elasticbeanstalk/latest/dg/using-features.customami.html)

7. After step 10 of the Amazon guide you can connect to your new custom eb EC2 instance and watch what it going on:

    $ tail -f /opt/elasticbeanstalk/var/log/hostmanager.log

That's what I've done.