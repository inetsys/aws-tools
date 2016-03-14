require 'thor'

module CliAWSTools

    class Eip < Thor
        include AWSTools

        desc 'attach', 'Attach EIP if available to this EC2 instance'
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

            association = AWSTools.ec2.describe_instances({
                instance_ids: [ec2_instance_id],
            }).reservations[0].instances[0].network_interfaces[0].association

            if association.ip_owner_id != 'amazon'
                AWSTools.logger.info "Already attached EIP #{association.public_ip}"
            else
                attached = false
                AWSTools.ec2.describe_addresses({
                    public_ips: AWSTools.available_eip
                }).addresses.each do |eip|
                    if eip.instance_id.nil?
                        if AWSTools.configuration.verbose
                            logger.debug "AWSTools.ec2.associate_address, public_ip = #{eip.public_ip}, instance_id = #{ec2_instance_id}"
                        else
                            AWSTools.ec2.associate_address({
                                public_ip: eip.public_ip,
                                instance_id: ec2_instance_id
                            })
                        end
                        attached = true
                        AWSTools.logger.info "Attached EIP #{eip.public_ip}"
                        break
                    end
                end

                if !attached
                    AWSTools.logger.warn "No free EIP available to attach"
                end
            end
        end

        desc 'list', 'List EIP for this EC2 instance'
        option :available, :type => :boolean, :default => false
        def list
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            addresses = AWSTools.ec2.describe_addresses({
                public_ips: AWSTools.available_eip
            }).addresses

            if options[:available]
                addresses.select {|eip| eip.instance_id.nil? }.map{|eip| public_ip}
            else
                addresses.map{|eip| public_ip}
            end
        end

    end
end