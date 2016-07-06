require 'thor'

module CliAWSTools

    class Ebs < Thor
        include AWSTools

        desc 'attach', 'Attach EBS volume.'
        long_desc <<-LONGDESC
        In order, first searches for an existing EBS volume detached from former EC2 instance,
        that should be shutting down at least. If not, searches for the most recent backup in
        snapshots. If this also fails, creates an empty new EBS volume
        LONGDESC
        option :name, :type => :string, :required => true
        option :mount_point, :type => :string, :required => true
        option :device, :type => :string, :required => true
        option :size, :type => :numeric, :default => 16
        def attach
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            # Search for an available web data EBS volume, searching by name
            # and the same Autoscaling Group as the EC2 instance
            volume_id = AWSTools.ebs_find_available_volume(options[:name])

            if volume_id.nil?
                # No volumes available, create a new one from a backup snapshot
                AWSTools.logger.info "No available web server EBS volumes found"

                # Search for last backup snapshot, searching by name
                snapshot_id = AWSTools.ebs_search_last_snapshot("Backup #{options[:name]}")

                volume_id = if snapshot_id.nil?
                    # No snapshots available, create a brand new EBS volume
                    AWSTools.logger.info "Creating new empty EBS volume in #{options[:mount_point]} with name '#{options[:name]}'"
                    AWSTools.ebs_create_new_volume(options[:name], "#{options[:mount_point]}", options[:size])
                else
                    # Create new volume from this snapshot and tag it
                    AWSTools.logger.info "Creating EBS volume from snapshot #{snapshot_id} with name '#{options[:name]}'"
                    AWSTools.ebs_create_volume_from_backup(snapshot_id, options[:name], options[:mount_point])
                end
            end

            # Attach volume to this EC2 instance
            AWSTools.logger.info "Attach #{volume_id} under device #{options[:device]}"
            AWSTools.ebs_attach_volume(volume_id, options[:device])
        end

        desc 'snapshot', 'Take EBS volume snapshot'
        option :name, :type => :string, :required => true
        option :mount_point, :type => :string, :required => true
        option :device, :type => :string, :required => true
        def snapshot
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            volume_id = AWSTools.ebs_attached_volume(options[:device])

            unless volume_id.nil?
                # 1. Freeze FS
                if AWSTools.configuration.dryrun
                    AWSTools.logger.info "[DryRun] Freeze FS under #{options[:mount_point]}"
                else
                    unless fs_freezed = system("sudo fsfreeze --freeze #{options[:mount_point]}")
                        # TODO try to unfreeze?
                        AWSTools.logger.warn "Cannot freeze #{options[:mount_point]}, snapshot could be corrupted"
                    else
                        AWSTools.logger.info "Volume #{options[:mount_point]} freezed"
                    end
                end

                begin
                    # 2. Take snapshot
                    snapshot_id = AWSTools.ebs_take_snapshot(volume_id, options[:device], options[:mount_point], "Backup #{options[:name]}")
                rescue
                    AWSTools.logger.error "Error taking #{options[:device]} EBS snapshot"
                else
                    AWSTools.logger.info "EBS snapshot #{snapshot_id} finished successfully"
                ensure
                    # 3. Unfreeze FS
                    if AWSTools.configuration.dryrun
                        AWSTools.logger.info "[DryRun] Unfreeze FS under #{options[:mount_point]}"
                    else
                        status = system("sudo fsfreeze --unfreeze #{options[:mount_point]}")
                        if fs_freezed
                            if status
                                AWSTools.logger.info "Volume #{options[:mount_point]} unfreezed"
                            else
                                AWSTools.logger.error "Cannot unfreeze #{options[:mount_point]}, projects will not run properly!"
                            end
                        end
                    end
                end
            else
                AWSTools.logger.warn "No #{options[:device]} EBS volume attached"
            end
        end

        desc 'delete-snapshot', 'Delete old EBS volume snapshots'
        option :name, :type => :string, :required => true
        option :days, :type => :numeric, :default => 7
        def delete_snapshot
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            snapshots = AWSTools.ec2.describe_snapshots({
                filters: [
                    {
                        name: "tag:Name",
                        values: ["Backup #{options[:name]}"],
                    },
                    {
                        name: "tag:StackName",
                        values: [AWSTools.configuration.stackname]
                    }
                ],
            }).snapshots.select {|x|
                x.start_time < (Time.now - options[:days] * 24 * 60 * 60)
            }.each {|x|
                AWSTools.ec2.delete_snapshot({
                    dry_run: options[:dryrun],
                    snapshot_id: x.snapshot_id
                })
                AWSTools.logger.info "Deleted snapshot #{x.snapshot_id} (#{x.start_time})"
            }
        end

    end
end