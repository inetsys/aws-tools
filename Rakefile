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
    namespace :ebs do
        desc 'Attach /var/www EBS volume.
    In order, first searches for an existing EBS volume detached from former EC2 instance,
    that should be shutting down at least. If not, searches for the most recent backup in
    snapshots. If this also fails, creates an empty new EBS volume'
        task :attach do
            @logger.progname = 'EC2'

            if !is_amazon_linux
                abort "This is not an EC2 instance"
            end

            # Search for an available web data EBS volume, searching by name
            # and the same Autoscaling Group as the EC2 instance
            volume_id = ebs_find_available_volume("Web server data disk")

            if volume_id.nil?
                # No volumes available, create a new one from a backup snapshot
                @logger.info "No available web server EBS volumes found"

                # Search for last backup snapshot, searching by name
                snapshot_id = ebs_search_last_snapshot("Backup Web server data disk")

                volume_id = if snapshot_id.nil?
                    # No snapshots available, create a brand new EBS volume
                    @logger.info "Creating new empty EBS volume for /var/www"
                    ebs_create_new_volume("Web server data disk", "/var/www", 16)
                else
                    # Create new volume from this snapshot and tag it
                    @logger.info "Creating EBS volume from snapshot #{snapshot_id}"
                    ebs_create_volume_from_backup(snapshot_id, "Web server data disk", "/var/www")
                end
            end

            # Attach volume to this EC2 instance
            ebs_attach_volume(volume_id, '/dev/xvdf')

        end
    end

    namespace :mysql do
        desc 'Attach local MySQL /mysqlvol EBS volume.
    In order, first searches for an existing EBS volume detached from former EC2 instance,
    that should be shutting down at least. If not, searches for the most recent backup in
    snapshots. If this also fails, creates an empty new EBS volume'
        task :attach do
            @logger.progname = 'EC2'

            if !is_amazon_linux
                abort "This is not an EC2 instance"
            end

            # Search for an available web data EBS volume, searching by name
            # and the same Autoscaling Group as the EC2 instance
            volume_id = ebs_find_available_volume("MySQL data disk")

            if volume_id.nil?
                # No volumes available, create a new one from a backup snapshot
                @logger.info "No available MySQL volumes found"

                # Search for last backup snapshot, searching by name
                snapshot_id = ebs_search_last_snapshot("Backup MySQL data disk")

                volume_id = if snapshot_id.nil?
                    # No snapshots available, create a brand new EBS volume
                    @logger.info "Creating new empty EBS volume for /mysqlvol"
                    ebs_create_new_volume("MySQL data disk", "/mysqlvol", 16)
                else
                    # Create new volume from this snapshot and tag it
                    @logger.info "Creating EBS volume from snapshot #{snapshot_id}"
                    ebs_create_volume_from_backup(snapshot_id, "MySQL data disk", "/mysqlvol")
                end
            end

            # First stop MySQL service
            system('sudo service mysql-default stop')
            # Attach MySQL volume to this EC2 instance
            ebs_attach_volume(volume_id, '/dev/xvdg')
            # Restart MySQL service
            system('sudo service mysql-default start')
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
