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
    desc 'Attach last web /var/www snapshot EBS'
    namespace :ebs do
        task :attach do
            @logger.progname = 'EC2'

            if !is_amazon_linux
                @logger.error "This is not an EC2 instance"
                next
            end

            snapshots = @ec2.describe_snapshots({
                filters: [
                    {
                        name: "tag:Name",
                        values: ["Backup data disk webserver"],
                    },
                ],
            }).snapshots.sort {|x,y| x.start_time <=> y.start_time}
            snapshot_id = snapshots.last.snapshot_id

            volume_id = @ec2.create_volume({
                snapshot_id: snapshot_id,
                availability_zone: ec2_availability_zone,
                volume_type: 'gp2',
            }).volume_id

            @ec2.create_tags({
                resources: [volume_id],
                tags: [
                    { key: "Environment", value: ec2_environment, },
                    { key: "Cliente", value: "Inetsys", },
                    { key: "Concepto", value: "Sistemas", },
                ],
            })

            # Wait until EBS volume is available
            begin
                @ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
                    w.interval = 10
                    w.max_attempts = 18
                end
            rescue Aws::Waiters::Errors::WaiterFailed
                @logger.error "EBS web data volume cannot be created"
            end

            @ec2.attach_volume({
                volume_id: volume_id,
                instance_id: ec2_instance_id,
                device: "/dev/xvdf",
            })

            # Wait until EBS volume is in use
            begin
                @ec2.wait_until(:volume_in_use, volume_ids:[volume_id]) do |w|
                    w.interval = 5
                    w.max_attempts = 10
                end
            rescue Aws::Waiters::Errors::WaiterFailed
                @logger.error "EBS web data volume cannot be attached"
            end

            # El problema de lo siguiente es que necesita un permiso demasiado amplio
            # para ejecutarse

            # @ec2.modify_instance_attribute({
            #     instance_id: ec2_instance_id,
            #     block_device_mappings: [
            #         {
            #             device_name: "/dev/xvdf",
            #             ebs: {
            #                 volume_id: volume_id,
            #                 delete_on_termination: true,
            #             },
            #         },
            #     ]
            # })
      end
    end

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
