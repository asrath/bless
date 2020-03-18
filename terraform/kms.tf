resource "aws_kms_key" "bless_key" {
  description             = "Bless KMS key to decrypt CA certificate"
  deletion_window_in_days = 10

  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage                = "ENCRYPT_DECRYPT"

  tags = {
    "owner"   = "${var.owner}"
    "project" = "${var.project}"
  }
}

resource "aws_kms_alias" "bless_key_alias" {
  name          = "alias/bless"
  target_key_id = "${aws_kms_key.bless_key.key_id}"
}
