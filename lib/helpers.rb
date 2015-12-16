# Helpers

module AWSTools
    def is_amazon_linux
        File.exist?('/etc/os-release') && (::File.open('/etc/os-release').read() =~ /Amazon Linux AMI/)
    end
end

include AWSTools

if is_amazon_linux
    @credentials = Aws::InstanceProfileCredentials.new
    @regionaws = File.read('/etc/aws_region').strip
else
    @credentials = Aws::SharedCredentials.new # Uses ENV['AWS_PROFILE']
    @regionaws = ENV['AWS_REGION']
end

@logger = Logger.new(STDOUT)
@logger.formatter = proc do |severity, datetime, progname, msg|
     "#{progname} - #{severity}: #{msg}\n"
end
@logger.level = Logger::INFO

@loggeraws = Logger.new(STDOUT)
@loggeraws.formatter = proc do |severity, datetime, progname, msg|
     "#{progname} - #{severity}: #{msg}\n"
end
@loggeraws.progname = 'AWSSDK'
@loggeraws.level = Logger::INFO

::Aws.config.update({
    region: @regionaws,
    credentials: @credentials,
    logger: @loggeraws
})

@ec2 = ::Aws::EC2::Client.new

@cloudformation = Aws::CloudFormation::Client.new

def ebs_search_last_snapshot(name)
    begin
        snapshots = @ec2.describe_snapshots({
            filters: [
                {
                    name: "tag:Name",
                    values: [name],
                },
            ],
        }).snapshots.sort {|x,y| x.start_time <=> y.start_time}
        snapshots.last.snapshot_id
    rescue
        @logger.warn "No #{name} snapshots available"
        nil
    end
end

def ebs_create_new_volume(name, mount_point, size=12)
    begin
        volume_id = @ec2.create_volume({
            availability_zone: ec2_availability_zone,
            volume_type: 'gp2',
            size: size,
            encrypted: false,
        }).volume_id

        ebs_tag_volume(volume_id, name, mount_point)

        # wait until is available
        @ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
            w.interval = 10
            w.max_attempts = 18
        end
    rescue # Aws::Waiters::Errors::WaiterFailed
        @logger.error "EBS #{name} cannot be created"
        raise
    end

    volume_id
end

def ebs_create_volume_from_backup(snapshot_id, name, mount_point)
    begin
        volume_id = @ec2.create_volume({
            snapshot_id: snapshot_id,
            availability_zone: ec2_availability_zone,
            volume_type: 'gp2',
        }).volume_id

        ebs_tag_volume(volume_id, name, mount_point)

        # wait until is available
        @ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
            w.interval = 10
            w.max_attempts = 18
        end

    rescue # Aws::Waiters::Errors::WaiterFailed
        @logger.error "EBS #{name} cannot be created"
        raise
    end

    volume_id
end

def ebs_attach_volume(volume_id, device)
    begin
        @ec2.attach_volume({
            volume_id: volume_id,
            instance_id: ec2_instance_id,
            device: device,
        })
        # wait until EBS volume is ready (status = in use)
        @ec2.wait_until(:volume_in_use, volume_ids:[volume_id]) do |w|
            w.interval = 10
            w.max_attempts = 18
        end
    rescue # Aws::Waiters::Errors::WaiterFailed
        @logger.error "EBS volume #{volume_id} cannot be attached to #{device}"
        raise
    end
end

def ebs_tag_volume(volume_id, name, mount_point)
    @ec2.create_tags({
        resources: [volume_id],
        tags: [
            { key: "Name", value: name, },
            { key: "Environment", value: ec2_environment, },
            { key: "Cliente", value: ec2_base_tags[:cliente], },
            { key: "Concepto", value: ec2_base_tags[:concepto], },
            { key: "Mount point", value: mount_point, },
            { key: "StackName", value: ec2_stackname, },
        ],
    })
end

def ebs_find_available_volume(name)
    volumes = @ec2.describe_volumes({
        filters: [
            {
                name: "tag:Name",
                values: [name],
            },
            {
                name: "tag:StackName",
                values: [ec2_stackname]
            },
            {
                name: "tag:Environment",
                values: [ec2_environment],
            }
        ],
    }).volumes

    volume_id = nil
    if volumes.count > 0
        volume_id = volumes.first.volume_id

        # wait until EBS volume is available
        begin
            @ec2.wait_until(:volume_available, volume_ids:[volume_id]) do |w|
                w.interval = 10
                w.max_attempts = 20
            end
        rescue Aws::Waiters::Errors::WaiterFailed
            @logger.error "EBS #{name} with id #{volume_id} has not been released by former EC2 instance"
            raise
        end
    end

    volume_id
end

def available_eip(stackname)
    mainStack = @cloudformation.describe_stacks(
        stack_name: stackname
    ).stacks[0].parameters.select{|v| v.parameter_key == 'ParentStackName' }[0].parameter_value

    poolIP = @cloudformation.describe_stacks(
        stack_name: mainStack
    ).stacks[0].parameters.select{|v| v.parameter_key == 'AvailableEIP' }[0].parameter_value

    poolIP.split(',')
end

def ec2_instance_id
    File.read('/etc/aws_instance_id').strip
end

def ec2_availability_zone
    File.read('/etc/aws_az').strip
end

def ec2_stackname
    tags = @ec2.describe_tags({
        filters: [{
            name: "resource-id",
            values: [ ec2_instance_id ]
        }]
    }).tags

    begin
        tags.select{|t| t.key=='aws:cloudformation:stack-name'}.first.value
    rescue
        raise "There is no aws:cloudformation:stack-name tag in this instance #{ec2_instance_id}"
    end
end

def ec2_environment
    tags = @ec2.describe_tags({
        filters: [{
            name: "resource-id",
            values: [ ec2_instance_id ]
        }]
    }).tags

    begin
        tags.select{|t| t.key=='Environment'}.first.value
    rescue
        raise "There is no Environment tag in this instance #{ec2_instance_id}"
    end
end

def ec2_base_tags
    tags = @ec2.describe_tags({
        filters: [{
            name: "resource-id",
            values: [ ec2_instance_id ]
        }]
    }).tags

    result = Hash.new
    result[:cliente] = begin
            tags.select{|t| t.key=='Cliente'}.first.value
        rescue
            'Inetsys'
        end
    result[:concepto] = begin
            tags.select{|t| t.key=='Concepto'}.first.value
        rescue
            'Sistemas'
        end

    result
end
