require 'logger'
require 'json'
require 'syslog/logger'
require 'fileutils'
require 'aws-sdk'
require_relative 'helpers'

include AWSTools

# do not color if running from cfn-init
require 'logger/colors' unless `ps aux | grep cfn-init | grep -v grep` != ""

@logger = Logger.new(STDOUT)
@logger.formatter = proc do |severity, datetime, progname, msg|
   "#{progname} - #{severity}: #{msg}\n"
end
@logger.level = Logger::INFO

task :default => ['help']

task :help do
    system("rake -sT")
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
