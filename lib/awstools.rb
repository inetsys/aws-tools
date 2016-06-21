# Helpers
require 'net/http'

module AWSTools
    class << self
        attr_accessor :configuration
        attr_accessor :logger
        attr_accessor :credentials
        attr_accessor :cloudformation
        attr_accessor :ec2
        attr_accessor :cloudwatch
        attr_accessor :aws_region
        attr_accessor :aws_profile
    end

    def self.is_amazon_linux
        File.exist?('/etc/os-release') && (::File.open('/etc/os-release').read() =~ /Amazon Linux AMI/)
    end

    def self.aws_region
        @aws_region ||= ec2_availability_zone.gsub(/[a-z]$/,'')
    end

    def self.aws_profile
        @aws_profile ||= 'sistemas'
    end

    def self.ec2_instance_id
        if is_amazon_linux
            uri = URI('http://169.254.169.254/latest/meta-data/instance-id')
            Net::HTTP.get(uri)
        else
            Kernel::abort "This is not an EC2 instance"
        end
    end

    def self.ec2_availability_zone
        if is_amazon_linux
            uri = URI('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            Net::HTTP.get(uri)
        else
            Kernel::abort "This is not an EC2 instance"
        end
    end

    def self.ec2_instance_type
        if is_amazon_linux
            uri = URI('http://169.254.169.254/latest/meta-data/instance-type')
            Net::HTTP.get(uri)
        else
            Kernel::abort "This is not an EC2 instance"
        end
    end

    def self.ec2_private_ip
        if is_amazon_linux
            uri = URI('http://169.254.169.254/latest/meta-data/local-ipv4')
            Net::HTTP.get(uri)
        else
            Kernel::abort "This is not an EC2 instance"
        end
    end

    def self.credentials
        @credentials ||= if is_amazon_linux
            Aws::InstanceProfileCredentials.new
        else
            Aws::SharedCredentials.new(
                profile_name: aws_profile
            )
        end
    end

    def self.ec2
        @ec2 ||= Aws::EC2::Client.new(
            region: aws_region,
            credentials: credentials,
            logger: logger
        )
    end

    def self.cloudformation
        @cloudformation ||= Aws::CloudFormation::Client.new(
            region: aws_region,
            credentials: credentials,
            logger: logger
        )
    end

    def self.cloudwatch
        @cloudwatch ||= Aws::CloudWatch::Client.new(
            region: aws_region,
            credentials: credentials,
            logger: logger
        )
    end

    def self.logger
        @logger ||= Logger.new(STDOUT).tap do |log|
            log.level = Logger::INFO
            log.progname = 'AWSSDK'
        end
    end

    def self.configuration
        @configuration ||= Configuration.new(ec2, ec2_instance_id)
    end

    def self.configure
        yield(configuration)
    end

    def self.abort(message)
        logger.error message
        Kernel::exit false
    end

    class Configuration
        attr_accessor :stackname
        attr_accessor :environment
        attr_accessor :tags
        attr_accessor :loggerchannel
        attr_accessor :verbose
        attr_accessor :dryrun

        def initialize(ec2_client, instance_id)
            current_tags = ec2_client.describe_tags({
                filters: [{
                    name: "resource-id",
                    values: [ instance_id ]
                }]
            }).tags

            @tags = Hash[current_tags.map{|t| [t.key, t.value]}]
            @stackname = tags['aws:cloudformation:stack-name'] || 'Staging-Web'
            @environment = tags['Environment']
            # begin
            #     @stackname = current_tags.select{|t| t.key=='aws:cloudformation:stack-name'}.first.value
            # rescue
            #     raise "There is no aws:cloudformation:stack-name tag in this instance #{ec2_instance_id}"
            # end

            # @tags = {
            #     'Environment' => begin current_tags.select{|t| t.key=='Environment'}.first.value rescue 'staging' end,
            #     'Cliente' => begin current_tags.select{|t| t.key=='Cliente'}.first.value rescue 'Inetsys' end,
            #     'Concepto' => begin current_tags.select{|t| t.key=='Concepto'}.first.value rescue 'Sistemas' end
            # }
        end

    end

    # Get the last snapshot with this name
    def self.ebs_search_last_snapshot(resource_name)
        begin
            snapshots = ec2.describe_snapshots({
                filters: [
                    {
                        name: "tag:Name",
                        values: [resource_name],
                    },
                ],
            }).snapshots.sort {|x,y| x.start_time <=> y.start_time}
            snapshots.last.snapshot_id
        rescue
            logger.warn "No #{name} snapshots available"
            nil
        end
    end

    # Create a new volume
    def self.ebs_create_new_volume(resource_name, mount_point, size=12)
        if configuration.dryrun
            logger.debug "#{__method__}, #{method(__method__).parameters.map { |arg| "#{arg[1].to_s} = #{eval arg[1].to_s}" }.join(', ')}"
            volume_id = 'vol-DRYRUN'
        else
            begin
                volume_id = ec2.create_volume({
                    availability_zone: ec2_availability_zone,
                    volume_type: 'gp2',
                    size: size,
                    encrypted: false,
                }).volume_id

                ebs_tag_volume(volume_id, resource_name, mount_point)

                # wait until is available
                ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
                    w.interval = 10
                    w.max_attempts = 18
                end
            rescue # Aws::Waiters::Errors::WaiterFailed
                logger.error "EBS #{name} cannot be created"
                raise
            end
        end

        volume_id
    end

    # Create a new volume from a snapshot
    def self.ebs_create_volume_from_backup(snapshot_id, name, mount_point)
        if configuration.dryrun
            logger.debug "#{__method__}, #{method(__method__).parameters.map { |arg| "#{arg[1].to_s} = #{eval arg[1].to_s}" }.join(', ')}"
            volume_id = 'vol-DRYRUN'
        else
            begin
                volume_id = ec2.create_volume({
                    snapshot_id: snapshot_id,
                    availability_zone: ec2_availability_zone,
                    volume_type: 'gp2',
                }).volume_id

                ebs_tag_volume(volume_id, name, mount_point)

                # wait until is available
                ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
                    w.interval = 10
                    w.max_attempts = 18
                end

            rescue # Aws::Waiters::Errors::WaiterFailed
                logger.error "EBS #{name} cannot be created"
                raise
            end
        end

        volume_id
    end

    def self.ebs_attach_volume(volume_id, device)
        if configuration.dryrun
            logger.debug "#{__method__}, #{method(__method__).parameters.map { |arg| "#{arg[1].to_s} = #{eval arg[1].to_s}" }.join(', ')}"
        else
            begin
                ec2.attach_volume({
                    volume_id: volume_id,
                    instance_id: ec2_instance_id,
                    device: device,
                })
                # wait until EBS volume is ready (status = in use)
                ec2.wait_until(:volume_in_use, volume_ids:[volume_id]) do |w|
                    w.interval = 10
                    w.max_attempts = 18
                end
            rescue # Aws::Waiters::Errors::WaiterFailed
                logger.error "EBS volume #{volume_id} cannot be attached to #{device}"
                raise
            end
        end
    end

    # Sets standard tags for EBS volume
    def self.ebs_tag_volume(volume_id, name, mount_point)
        if configuration.dryrun
            logger.debug "#{__method__}, #{method(__method__).parameters.map { |arg| "#{arg[1].to_s} = #{eval arg[1].to_s}" }.join(', ')}"
        else
            ec2.create_tags({
                resources: [volume_id],
                tags: [
                    { key: "Name", value: name, },
                    { key: "Environment", value: configuration.environment, },
                    { key: "Cliente", value: configuration.tags['Cliente'], },
                    { key: "Concepto", value: configuration.tags['Concepto'], },
                    { key: "Mount point", value: mount_point, },
                    { key: "StackName", value: configuration.stackname, },
                ],
            })
        end
    end

    # Busca un volumen disponible con ese nombre, para el mismo entorno
    # y el mismo Stack de Cloudformation
    def self.ebs_find_available_volume(name)
        volumes = ec2.describe_volumes({
            filters: [
                {
                    name: "tag:Name",
                    values: [name],
                },
                {
                    name: "tag:StackName",
                    values: [configuration.stackname]
                },
                {
                    name: "tag:Environment",
                    values: [configuration.environment],
                }
            ],
        }).volumes

        volume_id = nil
        if volumes.count > 0
            # TODO for more than 1 EC2 instance
            volume_id = volumes.first.volume_id

            # wait until EBS volume is available
            logger.info "Found volume #{volume_id}, waiting availability"
            begin
                ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
                    w.interval = 10
                    w.max_attempts = 20
                end
            rescue Aws::Waiters::Errors::WaiterFailed
                logger.error "EBS #{name} with id #{volume_id} has not been released by former EC2 instance"
                raise
            end
        end

        volume_id
    end

    # Devuelve el ID del volumen EBS
    # Argumentos:
    #    device_name (string) forma /dev/xvd[f-p]
    def self.ebs_attached_volume(device_name)
        mapping = ec2.describe_instances({
            instance_ids: [ec2_instance_id]
        }).reservations.first.instances.first.block_device_mappings

        begin
            mapping.select{|x| x.device_name == device_name }.first.ebs.volume_id
        rescue
            AWSTools.logger.debug "No device #{device_name}, only #{mapping.map{|x| x.device_name}}"
            nil
        end
    end

    # Crea un snapshot del volumen EBS indicado
    def self.ebs_take_snapshot(volume_id, device_name, mount_point, name)
        if configuration.dryrun
            logger.debug "#{__method__}, #{method(__method__).parameters.map { |arg| "#{arg[1].to_s} = #{eval arg[1].to_s}" }.join(', ')}"
            snapshot_id = 'snap-DRYRUN'
        else
            snapshot_id = ec2.create_snapshot({
                volume_id: volume_id,
                description: "Backup of #{device_name} volume under #{mount_point}",
            }).snapshot_id
            ec2.create_tags({
                resources: [snapshot_id],
                tags: [
                    { key: "Name", value: name, },
                    { key: "Environment", value: configuration.environment, },
                    { key: "Cliente", value: configuration.tags['Cliente'], },
                    { key: "Concepto", value: 'Backup', },
                    { key: "Mount point", value: mount_point, },
                    { key: "StackName", value: configuration.stackname, },
                ],
            })
        end

        snapshot_id
    end

    def self.available_eip
        # mainStack = cloudformation.describe_stacks(
        #     stack_name: stackname
        # ).stacks[0].parameters.select{|v| v.parameter_key == 'ParentStackName' }[0].parameter_value

        poolIP = cloudformation.describe_stacks(
            stack_name: configuration.stackname
        ).stacks[0].parameters.select{|v| v.parameter_key == 'AvailableEIP' }[0].parameter_value

        poolIP.split(',')
    end

end
