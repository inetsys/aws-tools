require 'thor'

module CliAWSTools

    class Eni < Thor
        include AWSTools

        desc 'attach', 'Attach ENI if available to this EC2 instance'
        def attach(eni_id, index)
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            attachment_id = AWSTools.ec2.attach_network_interface({
                dry_run: AWSTools.configuration.dryrun,
                network_interface_id: eni_id,
                instance_id: AWSTools.ec2_instance_id,
                device_index: index
            })

        end

        desc 'detach', 'Detach all ENIs in this EC2 instance'
        def detach
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            interfaces = AWSTools.ec2.describe_instances({
                instance_ids: [AWSTools.ec2_instance_id],
            }).reservations[0].instances[0].network_interfaces

            interfaces.each do |eni|
                if eni.attachment.status == 'attached'
                    AWSTools.ec2.detach_network_interface({
                        dry_run: AWSTools.configuration.dryrun,
                        attachment_id: eni.attachment.attachment_id,
                        force: true
                    })
                end
            end

        end

        desc 'assign PRIVATE_IPS', 'Assign new private IP list, separated by commas'
        def assign(private_ips)
            AWSTools.configure do |config|
                config.dryrun = options[:dryrun]
                config.verbose = options[:verbose]
            end
            AWSTools.logger.progname = 'EC2'
            AWSTools.logger.level = Logger::DEBUG if options[:verbose]

            unless AWSTools.is_amazon_linux
                AWSTools.abort "This is not an EC2 instance"
            end

            list_ip = private_ips.split(%r{,\s*})
            interfaces = AWSTools.ec2.describe_instances({
                instance_ids: [AWSTools.ec2_instance_id],
            }).reservations[0].instances[0].network_interfaces

            # get limits
            case AWSTools.ec2_instance_type
            when 't2.nano', 't2.micro'
                # two ENIs, 2 ip max. each
                # First primary private IP in first ENI (eth0) is fixed and cannot be changed
                if AWSTools.configuration.dryrun
                    AWSTools.logger.debug "#assign_private_ip_addresses, network_interface_id = #{interfaces.first.network_interface_id}, private_ip_addresses = #{list_ip[0]}, allow_reassignment = true"
                else
                    begin
                        AWSTools.ec2.unassign_private_ip_addresses({
                            network_interface_id: interfaces.first.network_interface_id,
                            private_ip_addresses: [ list_ip[0] ]
                        })
                    rescue Aws::EC2::Errors::InvalidParameterValue
                        AWSTools.logger.debug "Address #{list_ip[0]} not previously assigned"
                    end
                    AWSTools.ec2.assign_private_ip_addresses({
                        network_interface_id: interfaces.first.network_interface_id,
                        private_ip_addresses: [ list_ip[0] ],
                        allow_reassignment: true
                    })
                end
                if list_ip.count > 1
                    secondary_eni = AWSTools.ec2.create_network_interface({
                        dry_run: AWSTools.configuration.dryrun,
                        subnet_id: interfaces.first.subnet_id,
                        description: "Secondary ENI for Vpar",
                        groups: interfaces.first.groups.map {|g| g.group_id },
                        private_ip_addresses: list_ip[1..2].each_with_index.map { |item, index|
                            Hash[
                                private_ip_address: item,
                                primary: index == 0
                            ]
                        }
                    }).network_interface
                    AWSTools.ec2.attach_network_interface({
                        dry_run: AWSTools.configuration.dryrun,
                        network_interface_id: secondary_eni.network_interface_id,
                        instance_id: AWSTools.ec2_instance_id,
                        device_index: 1
                    })
                end
            when 't2.small'
                # two ENIs, 4 ip max. each
                # First primary private IP in first ENI (eth0) is fixed and cannot be changed
                if AWSTools.configuration.dryrun
                    AWSTools.logger.debug "#assign_private_ip_addresses, network_interface_id = #{interfaces.first.network_interface_id}, private_ip_addresses = #{list_ip[0]}, allow_reassignment = true"
                else
                    begin
                        AWSTools.ec2.unassign_private_ip_addresses({
                            network_interface_id: interfaces.first.network_interface_id,
                            private_ip_addresses: list_ip[0..2]
                        })
                    rescue Aws::EC2::Errors::InvalidParameterValue
                        AWSTools.logger.debug "Addresses #{list_ip[0..2]} not previously assigned"
                    end
                    AWSTools.ec2.assign_private_ip_addresses({
                        network_interface_id: interfaces.first.network_interface_id,
                        private_ip_addresses: list_ip[0..2],
                        allow_reassignment: true
                    })
                end
                if list_ip.count > 3
                    secondary_eni = AWSTools.ec2.create_network_interface({
                        dry_run: AWSTools.configuration.dryrun,
                        subnet_id: interfaces.first.subnet_id,
                        description: "Secondary ENI for Vpar",
                        groups: interfaces.first.groups.map {|g| g.group_id },
                        private_ip_addresses: list_ip[3..6].each_with_index.map { |item, index|
                            Hash[
                                private_ip_address: item,
                                primary: index == 0
                            ]
                        }
                    }).network_interface
                    AWSTools.ec2.attach_network_interface({
                        dry_run: AWSTools.configuration.dryrun,
                        network_interface_id: secondary_eni.network_interface_id,
                        instance_id: AWSTools.ec2_instance_id,
                        device_index: 1
                    })
                end
            else
                # at least 6 max. ip each
                # First primary private IP in first ENI (eth0) is fixed and cannot be changed
                begin
                    AWSTools.ec2.unassign_private_ip_addresses({
                        network_interface_id: interfaces.first.network_interface_id,
                        private_ip_addresses: list_ip[0..5]
                    })
                rescue Aws::EC2::Errors::InvalidParameterValue
                    AWSTools.logger.debug "Addresses #{list_ip[0..5]} not previously assigned"
                end
                AWSTools.ec2.assign_private_ip_addresses({
                    dry_run: AWS.configuration.dryrun,
                    network_interface_id: interfaces.first.network_interface_id,
                    private_ip_addresses: list_ip[0..5],
                    allow_reassignment: true
                })
            end

        end

    end
end