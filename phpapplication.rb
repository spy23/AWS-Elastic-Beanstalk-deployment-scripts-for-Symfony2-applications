#############################################################################
# AWS Elastic Beanstalk Host Manager
# Copyright 2011 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the “License”). You may
# not use this file except in compliance with the License. A copy of the
# License is located at
#
# http://aws.amazon.com/asl/
#
# or in the “license” file accompanying this file. This file is
# distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, express or implied. See the License for the specific
# language governing permissions and limitations under the License.
#
# File location: 
# /opt/elasticbeanstalk/srv/hostmanager/lib/elasticbeanstalk/hostmanager/applications/phpapplication.rb

require 'json'

module ElasticBeanstalk
  module HostManager
    module Applications

      class PHPApplication < Application
        class << self
          attr_reader :is_initialization_phase, :web_root_dir, :deploy_dir, :pre_deploy_script, :deploy_script, :post_deploy_script, :backup_dir, :error_start_index
        end

        # Directories, etc
        @web_root_dir       = '/var/www/html'
        @deploy_dir         = '/tmp/php-elasticbeanstalk-deployment'
        @pre_deploy_script  = '/tmp/php_pre_deploy_app.sh'
        @deploy_script      = '/tmp/php_deploy_app.sh'
        @post_deploy_script = '/tmp/php_post_deploy_app.sh'
        # Custom
        @backup_dir         = '/tmp'

        @is_initialization_phase = false

        def self.ensure_configuration
          HostManager.log 'Writing environment config'
          ElasticBeanstalk::HostManager::Utils::PHPUtil.write_sdk_config(ElasticBeanstalk::HostManager.config.application['Environment Properties'])

          HostManager.log 'Updating php.ini options'
          ElasticBeanstalk::HostManager::Utils::PHPUtil.update_php_ini(ElasticBeanstalk::HostManager.config.container['Php.ini Settings'])

          HostManager.log 'Updating Apache options'
          ElasticBeanstalk::HostManager::Utils::ApacheUtil.update_httpd_conf(ElasticBeanstalk::HostManager.config.container['Php.ini Settings'])
        end

        def mark_in_initialization
          @is_initialization_phase = true
        end

        def pre_deploy
          
          HostManager.log "Starting pre-deployment."

          application_version_url = @version_info.to_url

          # Custom: Backup vendors folder to seppd up time needed for each deployment.
          # Without these lines all vendors will be downloaded each time.
          # output = `/usr/bin/sudo /bin/mv #{PHPApplication.web_root_dir}/vendor #{PHPApplication.backup_dir} 2>&1`
          # HostManager.log "Output: #{output}"
          # raise "Failed to backup vendors" if $?.exitstatus != 0
          # Commented out because after moving the files this error occours:
          # "symfony" has local modifications. Please revert or commit/push them before running this command again.
          
          HostManager.log "Re-building the Deployment Directory"
          output = `/usr/bin/sudo /bin/rm -rf #{PHPApplication.deploy_dir}`
          HostManager.log "Output: #{output}"
          output = `/usr/bin/sudo /bin/mkdir -p #{PHPApplication.deploy_dir} 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to create #{PHPApplication.deploy_dir}" unless File.directory?(PHPApplication.deploy_dir)

          HostManager.log "Changing owner, groups and permissions for the deployment directory."
          output = `/usr/bin/sudo /bin/chown elasticbeanstalk:elasticbeanstalk #{PHPApplication.deploy_dir}`
          HostManager.log "Output: #{output}"
          output = `/usr/bin/sudo /bin/chmod -Rf 0777 #{PHPApplication.deploy_dir}`
          HostManager.log "Output: #{output}"

          HostManager.log "Downloading / Validating Application version #{@version_info.version} from #{application_version_url}"
          output = `/usr/bin/time -f %e /usr/bin/wget -v --tries=10 --retry-connrefused -o #{PHPApplication.deploy_dir}/wget.log -O #{PHPApplication.deploy_dir}/application.zip "#{application_version_url}" 2>&1`
          HostManager.log "Output: #{output}"
          raise "Application download from #{application_version_url} failed" unless File.exists?("#{PHPApplication.deploy_dir}/application.zip")

          output = output.to_f * 1000
          HostManager.log "Application Download Time (ms): #{output}"
          HostManager.state.context[:metric].timings['AppDownloadTime'] = output unless HostManager.state.context[:metric].nil?

          output = `grep -o '(\\(.*\\/s\\))' #{PHPApplication.deploy_dir}/wget.log | sed 's/[\\(\\)]//g' 2>&1` if File.exists?("#{PHPApplication.deploy_dir}/wget.log")
          if output =~ /([0-9]+(?:\.[0-9]*))\s+(KB|MB|GB).*/
            output = $~[1].to_f
            output *= 1024 if $~[2] == 'MB' || $~[2] == 'GB'
            output *= 1024 if $~[2] == 'GB'
            output = output.to_i
            HostManager.log "Application Download Rate (kb/s): #{output}"
            HostManager.state.context[:metric].counters['AppDownloadRate'] = output unless HostManager.state.context[:metric].nil?
          elsif
            HostManager.log "Application Download Rate could not be determined: #{output}"
          end

          output = `/usr/bin/openssl dgst -md5 #{PHPApplication.deploy_dir}/application.zip 2>&1`
          output = $~[1] if output =~ /MD5\([^\)]+\)= (.*)/
          HostManager.log "Output: #{output}"
          raise "Application digest (#{output}) does not match expected digest (#{@version_info.digest})" unless output == @version_info.digest

        rescue
          HostManager.log("Version #{@version_info.version} PRE-DEPLOYMENT FAILED: #{$!}\n#{$@.join('\n')}")
          ex = ElasticBeanstalk::HostManager::DeployException.new("Version #{@version_info.version} pre-deployment failed: #{$!}")
          ex.output = output || ''
          raise ex
        end

        def deploy
          HostManager.log "Starting deployment."

          HostManager.log "Changing owner, groups and permissions for the deployment directory."
          output = `/usr/bin/sudo /bin/chown elasticbeanstalk:elasticbeanstalk #{PHPApplication.deploy_dir}`
          HostManager.log "Output: #{output}"
          output = `/usr/bin/sudo /bin/chmod -Rf 0777 #{PHPApplication.deploy_dir}`
          HostManager.log "Output: #{output}"

          HostManager.log "Creating #{PHPApplication.deploy_dir}/application and #{PHPApplication.deploy_dir}/backup"
          output = `/bin/mkdir -p #{PHPApplication.deploy_dir}/application 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to create #{PHPApplication.deploy_dir}/application" if $?.exitstatus != 0

          output = `/bin/mkdir -p #{PHPApplication.deploy_dir}/backup 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to create #{PHPApplication.deploy_dir}/backup" if $?.exitstatus != 0

          HostManager.log "Unzipping #{PHPApplication.deploy_dir}/application.zip to #{PHPApplication.deploy_dir}/application"
          output = `/usr/bin/unzip -o #{PHPApplication.deploy_dir}/application.zip -d #{PHPApplication.deploy_dir}/application 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to unzip #{PHPApplication.deploy_dir}/application.zip" if $?.exitstatus != 0

          HostManager.log "Re-building #{PHPApplication.web_root_dir}"
          output = `/usr/bin/sudo /bin/rm -Rf #{PHPApplication.web_root_dir} 2>&1`
          HostManager.log "Output: #{output}"
          output = `/usr/bin/sudo /bin/mkdir -p #{PHPApplication.web_root_dir}/ 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to create #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          # Custom: Install vendors from backup. See above.
          # output = `/usr/bin/sudo /bin/mv #{PHPApplication.backup_dir}/vendor #{PHPApplication.web_root_dir} 2>&1`
          # HostManager.log "Output: #{output}"
          # raise "Failed to install backuped vendors" if $?.exitstatus != 0

          output = `/usr/bin/sudo /bin/chown -Rf elasticbeanstalk:elasticbeanstalk #{PHPApplication.web_root_dir} 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to set group / owner of #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          output = `/usr/bin/sudo /bin/chmod -Rf 0755 #{PHPApplication.web_root_dir} 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to set mode of #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          HostManager.log "Moving and adjusting application permissions"
          output = `/usr/bin/sudo /bin/mv -n #{PHPApplication.deploy_dir}/application/{,.}?* #{PHPApplication.web_root_dir} 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to move application to #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          output = `/usr/bin/sudo /bin/chown -Rf elasticbeanstalk:elasticbeanstalk #{PHPApplication.web_root_dir} 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to set owner / group of application deployed to #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          output = `/usr/bin/sudo /bin/chmod -Rf 0755 #{PHPApplication.web_root_dir} 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to set mode of application deployed to #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          output = `/bin/find #{PHPApplication.web_root_dir} -type f -print0 | /usr/bin/xargs -0 /bin/chmod 0644 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to set final mode of application files deployed to #{PHPApplication.web_root_dir}" if $?.exitstatus != 0

          ElasticBeanstalk::HostManager::Utils::BluepillUtil.start_target("httpd") if @is_initialization_phase

          # Custom deployment tasks
          HostManager.log "Start custom deployment tasks"
          
          # Install vendors
          output = `/usr/bin/sudo /usr/bin/php #{PHPApplication.web_root_dir}/bin/vendors install 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to install vendors" if $?.exitstatus != 0
          
          # Create Entities
          output = `/usr/bin/sudo /usr/bin/php #{PHPApplication.web_root_dir}/app/console doctrine:generate:entities Quilt --path=src/ --no-backup 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to create entities" if $?.exitstatus != 0
          
          # Create Database Tables
          output = `/usr/bin/sudo /usr/bin/php #{PHPApplication.web_root_dir}/app/console doctrine:schema:update --force --env="prod" 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to create database tables" if $?.exitstatus != 0
          
          # Fixtures 
          # Commented out because the fixture load command purgeds the database first. 
          # "php app/console doctrine:fixtures:load --env="prod" --append" was no solution because it throws an error if the data already exists
          # output = `/usr/bin/sudo /usr/bin/php #{PHPApplication.web_root_dir}/app/console doctrine:fixtures:load --env="prod" 2>&1`
          # HostManager.log "Output: #{output}"
          # raise "Failed to load database fixtures" if $?.exitstatus != 0
          
          # Install app assets 
          output = `/usr/bin/sudo /usr/bin/php #{PHPApplication.web_root_dir}/app/console assets:install #{PHPApplication.web_root_dir}/web 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to load database fixtures" if $?.exitstatus != 0
          
          # Clear the cache prod
          output = `/usr/bin/sudo /usr/bin/php #{PHPApplication.web_root_dir}/app/console cache:clear --env="prod" 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to clear the prod cache" if $?.exitstatus != 0
          
          # Set directory permissions 
          output = `/usr/bin/sudo setfacl -R -m u:ec2-user:rwx #{PHPApplication.web_root_dir}/app/logs/ #{PHPApplication.web_root_dir}/app/cache/ 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to set directory permissions 1" if $?.exitstatus != 0
          output = `/usr/bin/sudo setfacl -R -m u:elasticbeanstalk:rwx #{PHPApplication.web_root_dir}/app/logs/ #{PHPApplication.web_root_dir}/app/cache/ 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to set directory permissions 2" if $?.exitstatus != 0
          output = `/usr/bin/sudo setfacl -dR -m u:ec2-user:rwx #{PHPApplication.web_root_dir}/app/logs/ #{PHPApplication.web_root_dir}/app/cache/ 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to set directory permissions 3" if $?.exitstatus != 0
          output = `/usr/bin/sudo setfacl -dR -m u:elasticbeanstalk:rwx #{PHPApplication.web_root_dir}/app/logs/ #{PHPApplication.web_root_dir}/app/cache/ 2>&1`
          HostManager.log "Output: #{output}"
          raise "Failed to set directory permissions 4" if $?.exitstatus != 0
          
          # Create custom folders
          output = `/usr/bin/sudo /bin/chown -Rf elasticbeanstalk:elasticbeanstalk #{PHPApplication.web_root_dir}/web/data 2>&1`
          HostManager.log "Output: #{output}"
          raise "Unable to set owner / group of folder #{PHPApplication.web_root_dir}/web/data" if $?.exitstatus != 0
          
          # Execute custom php script for additional deplayoment tasks. This enables you to add some tasks w/o the need to create a new AMI every time.
          output = `/usr/bin/sudo /usr/bin/php -f #{PHPApplication.web_root_dir}/eb_deploy.php 2>&1`
          HostManager.log "Output: #{output}"
          raise "Some error occured during iexecution of custom eb_deploy.php script" if $?.exitstatus != 0
          
          HostManager.log "End custom deployment tasks"
          # End custom deployment hook
	  
        rescue
          HostManager.log("Version #{@version_info.version} DEPLOYMENT FAILED: #{$!}\n#{$@.join('\n')}")
          ex = ElasticBeanstalk::HostManager::DeployException.new("Version #{@version_info.version} deployment failed: #{$!}")
          ex.output = output || ''
          raise ex
        end

        def post_deploy
          HostManager.log "Starting post-deployment."
          HostManager.log "[No tasks.]"
        end

      end # PHPApplication class

    end
  end
end