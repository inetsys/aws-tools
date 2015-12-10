# AWS Tools

General tools to use on EC2 instances

## Autoassign EIP

There's a task *ec2:eip:attach* to discover available EIP on this account, and
attach one of them to this instance.

If there was an EIP already attached, exits with a message and does nothing. It
does not reassign a new EIP.

### Cloudformation Stack

It gets the available EIP list from a Stack parameter `AvailableEIP`, which is
defined in the main Stack. The EC2 instances are launched in a substack, so
we need first the parameter `ParentStackName`, containing the name of the
main Cloudformation Stack that contains this one.

### IAM permissions

The EC2 instance must have the following permissions. For example, in its
IAM Instance Profile.

    {
      "Sid": "CloudFormationInfo",
      "Effect": "Allow",
      "Action": [
        "cloudformation:DescribeStacks"
      ],
      "Resource": [
        { "Fn::Join" : ["", [
          "arn:aws:cloudformation:",
          { "Ref" : "AWS::Region" },
          ":",
          { "Ref" : "AWS::AccountId" },
          ":stack/",
          { "Ref" : "ParentStackName" },
          "/*"
        ]]},
        { "Fn::Join" : ["", [
          "arn:aws:cloudformation:",
          { "Ref" : "AWS::Region" },
          ":",
          { "Ref" : "AWS::AccountId" },
          ":stack/",
          { "Ref" : "AWS::StackName" },
          "/*"
        ]]}
      ]
    },
    {
      "Sid": "EIPManage",
      "Effect": "Allow",
      "Action": [
        "ec2:AssociateAddress",
        "ec2:DescribeAddresses",
        "ec2:EIPAssociation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Info",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }