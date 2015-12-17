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
    desc 'Checks main instance on Autoscaling Group.
    For all the EC2 instances in the same Autoscaling Group, checks if this is
    the one marked as master instance, which means it is the reference for taking
    snapshots and other backups'
    task :is_master do
        unless is_amazon_linux
            abort "This is not an EC2 instance"
        end

        # For right now, as there is only one instance in group, always return true
        @logger.info 'This is the master EC2 instance'
        exit 0
    end

    desc 'Checks if this is production env'
    task :is_production do
        unless is_amazon_linux
            abort "This is not an EC2 instance"
        end

        exit ec2_environment == 'production'
    end

    namespace :www do
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

        desc 'Take /var/www EBS snapshot.
    Creates a new snapshot of /var/www EBS volume'
        task :snapshot do
            @logger.progname = 'EC2'

            if !is_amazon_linux
                abort "This is not an EC2 instance"
            end

            volume_id = ebs_attached_volume("/dev/xvdf")

            unless volume_id.nil?
                # 1. Freeze FS
                unless fs_freezed = system("sudo fsfreeze --freeze /var/www")
                    @logger.warn 'Cannot freeze Web data volume, snapshot could be corrupted'
                else
                    @logger.info 'Volume /var/www freezed'
                end
                begin
                    # 2. Take snapshot
                    snapshot_id = ebs_take_snapshot(volume_id, "/dev/xvdf", "/var/www", "Backup Web server data disk")
                rescue
                    @logger.error "Error taking /var/www EBS snapshot"
                else
                    @logger.info "EBS snapshot #{snapshot_id} finished successfully"
                ensure
                    # 3. Unfreeze FS
                    if fs_freezed
                        unless system('sudo fsfreeze --unfreeze /var/www')
                            @logger.error "Cannot unfreeze /var/www, projects will not run properly!"
                        else
                            @logger.info 'Volume /var/www unfreezed'
                        end
                    end
                end
            else
                @logger.warn "No /var/www EBS volume attached"
            end
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

        desc 'Take /mysqlvol EBS snapshot.
    Creates a new snapshot of /mysqlvol EBS volume'
        task :snapshot do
            @logger.progname = 'EC2'

            if !is_amazon_linux
                abort "This is not an EC2 instance"
            end

            volume_id = ebs_attached_volume("/dev/xvdf")

            unless volume_id.nil?
                # 1. Stop mysql server
                unless mysql_stopped = system('sudo service mysql-default stop')
                    @logger.warn 'Cannot stop MySQL server, snapshot could be corrupted'
                else
                    @logger.info 'MySQL server stopped'
                end
                # 2. Freeze FS
                unless fs_freezed = system("sudo fsfreeze --freeze /mysqlvol")
                    @logger.warn 'Cannot freeze MySQL data volume, snapshot could be corrupted'
                else
                    @logger.info 'Volume /mysqlvol freezed'
                end
                # 3. Take snapshot
                begin
                    snapshot_id = ebs_take_snapshot(volume_id, "/dev/xvdg", "/mysqlvol", "Backup MySQL data disk")
                rescue
                    @logger.error "Error taking /mysqlvol EBS snapshot"
                else
                    @logger.info "EBS snapshot #{snapshot_id} finished"
                ensure
                    # 4. Unfreeze FS
                    if fs_freezed
                        unless system('sudo fsfreeze --unfreeze /mysqlvol')
                            @logger.error "Cannot unfreeze /mysqlvol, MySQL will not run!"
                        else
                            @logger.info 'Volume /mysqlvol unfreezed'
                        end
                    end
                    # 5. Restart mysql server
                    if mysql_stopped
                        unless system('sudo service mysql-default start')
                           @logger.error "Cannot start MySQL after snapshot!"
                        else
                            @logger.info 'MySQL server started'
                        end
                    end
                end
            else
                @logger.warn "No /mysqlvol EBS volume attached"
            end
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
