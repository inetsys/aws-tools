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
  @credentials = Aws::SharedCredentials.new(
    profile_name: 'sistemas'
  )
  @regionaws = 'eu-central-1'
end

::Aws.config.update({
  region: @regionaws,
  credentials: @credentials
})

@ec2 = ::Aws::EC2::Client.new

@cloudformation = Aws::CloudFormation::Client.new

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
