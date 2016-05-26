require 'logger'
require 'json'
require 'syslog/logger'
require 'fileutils'

include AWSTools

# do not color if running from cfn-init
require 'logger/colors' unless `ps aux | grep cfn-init | grep -v grep` != ""

task :default => ['help']

task :help do
    system("rake -sT")
end

namespace :chef do
    desc 'Checks for last version of Chef cookbooks'
    task :needsupdate do
        Dir.chdir('/var/chef/chef-repo') do
            last_version = %x(git ls-remote --tags origin | cut -f 2 | grep -v "\\^{}" | awk -F/ '{ print $3 }' | sort -V | tail -1)
            current_version = %x(env -i git describe --abbrev=0 HEAD)

            logger.info "Last version: #{last_version}"
            logger.info "Current version: #{current_version}"

            # Return status code 0 if differ (success), indicating it has to be updated
            exit last_version != current_version
        end
    end
end
