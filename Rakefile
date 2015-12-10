require 'logger'
require 'json'
require 'syslog/logger'
require 'fileutils'
require 'aws-sdk'
require_relative 'lib/helpers'

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

      # Return status code 0 if differ (success), indicating it has to be updated
      exit last_version != current_version
    end
  end
end

namespace :ec2 do
    namespace :eip do
        desc 'Attach EIP if available to this EC2 instance'
        task :attach do |t,args|
          @logger.progname = 'EC2'

          if !is_amazon_linux
            @logger.error "This is not an EC2 instance"
            next
          end

          association = @ec2.describe_instances({
            instance_ids: [ec2_instance_id],
          }).reservations[0].instances[0].network_interfaces[0].association
          if association.ip_owner_id != 'amazon'
            @logger.info "Already attached EIP #{association.public_ip}"
          else
            attached = false
            @ec2.describe_addresses({
              public_ips: available_eip(ec2_stackname)
            }).addresses.each do |eip|
              if eip.instance_id.nil?
                @ec2.associate_address({
                  public_ip: eip.public_ip,
                  instance_id: ec2_instance_id
                })
                attached = true
                @logger.info "Attached EIP #{eip.public_ip}"
                break
              end
            end

            if !attached
              @logger.warn "No free EIP available to attach"
            end
          end
        end
    end
end
