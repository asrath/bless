resource "aws_lambda_function" "bless_lambda" {
  function_name = "${var.function_name}"
  description   = "Lambda that signs public keys for users and hosts"

  handler = "bless_lambda.lambda_handler"
  runtime = "python3.7"
  timeout = 10

  role = "${aws_iam_role.lambda_kms_role.arn}"

  filename         = "../publish/bless_lambda.zip"
  source_code_hash = "${filebase64sha256("../publish/bless_lambda.zip")}"

  publish = false

  tags = {
    "owner"   = "${var.owner}"
    "project" = "${var.project}"
  }
}
