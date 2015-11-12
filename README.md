# AWS Tools

General tools to use on EC2 instances

## Autoassign EIP

There's a task *ec2:eip:attach* to discover available EIP on this account, and
attach one of them to this instance.

If there was an EIP already attach, exists with a message an does nothing. It
does not reassign a new EIP.
