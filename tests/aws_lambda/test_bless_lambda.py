from unittest import mock

from bless.aws_lambda import bless_lambda
from tests.ssh.vectors import EXAMPLE_RSA_PUBLIC_KEY

HOST_REQUEST = {
    'hostnames': 'host.example.com',
    'public_key_to_sign': EXAMPLE_RSA_PUBLIC_KEY
}

USER_REQUEST = {
    "remote_usernames": "user",
    "public_key_to_sign": EXAMPLE_RSA_PUBLIC_KEY,
    "bastion_user": "user"
}


@mock.patch('bless.aws_lambda.bless_lambda.lambda_handler_user')
def test_user_request(mock_func):
    bless_lambda.lambda_handler(USER_REQUEST)
    mock_func.assert_called()


@mock.patch('bless.aws_lambda.bless_lambda.lambda_handler_host')
def test_host_request(mock_func):
    bless_lambda.lambda_handler(HOST_REQUEST)
    mock_func.assert_called()
