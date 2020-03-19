data "aws_iam_policy" "aws_lambda_basic_execution" {
  arn = "${var.aws_lambda_basic_execution_role_arn}"
}

data "aws_iam_policy" "aws_ssm" {
  arn = "${var.aws_ssm_managed_instance_core_arn}"
}

resource "aws_iam_policy" "kms_policy" {
  name        = "${var.owner}-kms-bless"
  path        = "/"
  description = "KMS policy for bless"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
            "kms:Decrypt",
            "kms:Encrypt"
        ],
        "Resource": "*"
      }
    ]
}
EOF
}

resource "aws_iam_role" "lambda_kms_role" {
  name = "${var.owner}-${var.project}-lambda-${aws_iam_policy.kms_policy.name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_kms_role" {
  role       = "${aws_iam_role.lambda_kms_role.name}"
  policy_arn = "${aws_iam_policy.kms_policy.arn}"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = "${aws_iam_role.lambda_kms_role.name}"
  policy_arn = "${data.aws_iam_policy.aws_lambda_basic_execution.arn}"
}

resource "aws_iam_policy" "bless_lambda_invoke_policy" {
  name        = "${var.owner}-bless-invoke-${var.function_name}"
  path        = "/"
  description = "Policy to allow bless lambda invocation"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Sid": "VisualEditor0",
          "Effect": "Allow",
          "Action": "lambda:InvokeFunction",
          "Resource": "arn:aws:lambda:eu-west-1:854849375651:function:SSHCA"
      }
  ]
}
EOF
}

resource "aws_iam_role" "ec2_instance_role" {
  name = "${var.owner}-${var.project}-instance-invoke-${var.function_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2_instance_role_invoke_bless_lambda" {
  role       = "${aws_iam_role.ec2_instance_role.name}"
  policy_arn = "${aws_iam_policy.bless_lambda_invoke_policy.arn}"
}

resource "aws_iam_role_policy_attachment" "ec2_instance_ssm" {
  role       = "${aws_iam_role.ec2_instance_role}"
  policy_arn = "${data.aws_iam_policy.aws_ssm}"
}
