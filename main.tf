data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}


variable main_region {
  description = "Main region for creating required IAM roles."
  type = string
  default = "eu-west-1"
}


resource "aws_ssm_document" "automation_runbook_enable_default_ssm" {
  name = "automationRunbookEnableDefaultSSM"
  document_type = "Automation"
  document_format = "JSON"

  content = jsonencode({
    description = "This document updates the Systems Manager service setting `default-ec2-instance-management-role`."
    schemaVersion = "0.3"
    assumeRole = "{{ AutomationAssumeRole }}"
    parameters = {
      AutomationAssumeRole = {
        type = "AWS::IAM::Role::Arn"
        description = "(Required) The ARN of the role that allows Automation to perform the actions on your behalf."
        default = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/AutomationServiceRole-EnableDefaultSSM"
      }
      DefaultEC2InstanceManagementRoleName = {
        type = "String"
        description = "(Required) The name of the default EC2 instance management role."
        default = "AWSSystemsManagerDefaultEC2InstanceManagementRole"
      }
    }
    mainSteps = [
      {
        name = "checkExistingServiceSetting"
        action = "aws:executeAwsApi"
        onFailure = "Abort"
        inputs = {
          Service = "ssm"
          Api = "GetServiceSetting"
          SettingId = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
        }
        outputs = [
          {
            Name = "ServiceSettingValue"
            Type = "String"
            Selector = "$.ServiceSetting.SettingValue"
          }
        ]
      },
      {
        name = "branchOnSetting"
        action = "aws:branch"
        isEnd = "True"
        inputs = {
          Choices = [
            {
              NextStep = "updateServiceSetting"
              Not = {
                Variable = "{{ checkExistingServiceSetting.ServiceSettingValue }}"
                StringEquals = "{{ DefaultEC2InstanceManagementRoleName }}"
              }
            }
          ]
        }
      },
      {
        name = "updateServiceSetting"
        action = "aws:executeAwsApi"
        onFailure = "Abort"
        inputs = {
          Service = "ssm"
          Api = "UpdateServiceSetting"
          SettingId = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
          SettingValue = "{{ DefaultEC2InstanceManagementRoleName }}"
        }
      },
      {
        name = "confirmServiceSetting"
        action = "aws:executeAwsApi"
        onFailure = "Abort"
        inputs = {
          Service = "ssm"
          Api = "GetServiceSetting"
          SettingId = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
        }
        outputs = [
          {
            Name = "ServiceSetting"
            Type = "StringMap"
            Selector = "$.ServiceSetting"
          }
        ]
      }
    ]
  })
}

resource "aws_ssm_association" "update_default_ec2_instance_management_association" {
  association_name = "EnableDefaultEC2InstanceManagement"
  name = aws_ssm_document.automation_runbook_enable_default_ssm.name
#  name = aws_ssm_document.automation_runbook_enable_default_ssm.created_date
#  wait_for_success_timeout_seconds = 300
}

resource "aws_iam_role" "automation_service_role" {
 # count = locals.IsMainRegion ? 1 : 0
  name = "AutomationServiceRole-EnableDefaultSSM"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
  path = "/"
  managed_policy_arns = [aws_iam_policy.automation_service_role_policy.arn]
}

resource "aws_iam_policy" "automation_service_role_policy" {
#  count = locals.IsMainRegion ? 1 : 0
  name = "enableDefaultSSM"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateServiceSetting"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:servicesetting/arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role",
          "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetServiceSetting"
        ]
        Resource = [
          "*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.managed_instance_role.arn
        ]
        Condition = {
          StringLikeIfExists = {
            "iam:PassedToService" = "ssm.amazonaws.com"
          }
        }
      }
    ]
  })
  // CF Property(Roles) = [
  //   aws_iam_role.automation_service_role[0].arn
  // ]
}

resource "aws_iam_instance_profile" "automation_instance_profile" {
  name = "automationServiceRole"
#  name = "AutomationInstanceProfile-EnableDefaultSSM"
  role = aws_iam_role.automation_service_role.name
#  role = [
##    aws_iam_role.automation_service_role.arn
#    aws_iam_role.automation_service_role[0].arn
#  ]
}

resource "aws_iam_role" "managed_instance_role" {
 # count = locals.IsMainRegion ? 1 : 0
  name = "AWSSystemsManagerDefaultEC2InstanceManagementRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ssm.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
  managed_policy_arns = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"]
#  path = "/"  # removed to test managed_policy creation
}
