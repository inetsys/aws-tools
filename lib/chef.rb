require 'thor'

module CliAWSTools

    class Chef < Thor
        include AWSTools

        desc 'needsupdate', 'Checks for last version of Chef cookbooks'
        def needsupdate
            Dir.chdir('/var/chef/chef-repo') do
                last_version = %x(git ls-remote --tags origin | cut -f 2 | grep -v "\\^{}" | awk -F/ '{ print $3 }' | sort -V | tail -1)
                current_version = %x(env -i git describe --abbrev=0 HEAD)

                # Return status code 0 if differ (success), indicating it has to be updated
                exit last_version != current_version
            end
        end

    end
end