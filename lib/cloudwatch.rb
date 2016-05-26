require 'thor'

class Cloudwatch < Thor
    include AWSTools

# "RootDiskAlarm" : {
#       "Type" : "AWS::CloudWatch::Alarm",
#       "Condition": "ActiveMonitoring",
#       "Properties" : {
#         "AlarmDescription" : "Excessive root disk occupation for Web Servers",
#         "AlarmActions" : [ { "Ref" : "AlarmSNSTopic" } ],
#         "MetricName" : "DiskSpaceUtilization",
#         "Namespace" : "System/Linux",
#         "Statistic" : "Average",
#         "Period" : "900",
#         "EvaluationPeriods" : "2",
#         "Threshold" : "85",
#         "Unit": "Percent",
#         "ComparisonOperator" : "GreaterThanThreshold",
#         "Dimensions" : [
#           {
#             "Name": "AutoScalingGroupName",
#             "Value": { "Ref": "GaruServerAutoscalingGroup" }
#           },
#           {
#             "Name" : "MountPath",
#             "Value" : "/"
#           },
#           {
#             "Name" : "Filesystem",
#             "Value" : "/dev/xvda1"
#           }
#         ]
#       }
#     },

#     "DataDiskAlarm" : {
#       "Type" : "AWS::CloudWatch::Alarm",
#       "Condition": "ActiveMonitoring",
#       "Properties" : {
#         "AlarmDescription" : "Excessive data disk (/var/www) occupation for Web Server",
#         "AlarmActions" : [ { "Ref" : "AlarmSNSTopic" } ],
#         "MetricName" : "DiskSpaceUtilization",
#         "Namespace" : "System/Linux",
#         "Statistic" : "Average",
#         "Period" : "900",
#         "EvaluationPeriods" : "2",
#         "Threshold" : "85",
#         "Unit": "Percent",
#         "ComparisonOperator" : "GreaterThanThreshold",
#         "Dimensions" : [
#           {
#             "Name": "AutoScalingGroupName",
#             "Value": { "Ref": "GaruServerAutoscalingGroup" }
#           },
#           {
#             "Name" : "MountPath",
#             "Value" : "/var/www"
#           },
#           {
#             "Name" : "Filesystem",
#             "Value" : "/dev/xvdf"
#           }
#         ]
#       }
#     },

#     "MemoryAlarm" : {
#       "Type" : "AWS::CloudWatch::Alarm",
#       "Condition": "ActiveMonitoring",
#       "Properties" : {
#         "AlarmDescription" : "Memory usage for Web Server",
#         "AlarmActions" : [ { "Ref" : "AlarmSNSTopic" } ],
#         "MetricName" : "MemoryUtilization",
#         "Namespace" : "System/Linux",
#         "Statistic" : "Average",
#         "Period" : "300",
#         "EvaluationPeriods" : "2",
#         "Threshold" : "90",
#         "Unit": "Percent",
#         "ComparisonOperator" : "GreaterThanThreshold",
#         "Dimensions" : [ {
#             "Name": "AutoScalingGroupName",
#             "Value": { "Ref": "GaruServerAutoscalingGroup" }
#           } ]
#       }
#     }

    desc 'create', 'Creates basic Alarms for this instance in Cloudwatch'
    def create
        cloudwatch.describe_alarms
    end
end