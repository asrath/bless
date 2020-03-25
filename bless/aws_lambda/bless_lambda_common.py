"""
.. module: bless.aws_lambda.bless_lambda_common
    :copyright: (c) 2016 by Netflix Inc., see AUTHORS for more
    :license: Apache, see LICENSE for more details.
"""
import logging
import os

import boto3
from bless.cache.bless_lambda_cache import BlessLambdaCache
from bless.config.bless_config import BlessConfig
from bless.config import bless_config
from bless.request.bless_request_user import BlessUserRequest

global_bless_cache = None


def success_response(cert, ca_public_key=None):
    response = {
        'certificate': cert
    }

    region = os.environ.get("AWS_REGION")

    if ca_public_key is not None:
        response['ca_pub_key'] = str(ca_public_key)
        response['client_ca'] = [
            f'@cert-authority *.{region}.compute.amazonaws.com',
            f'@cert-authority *.{region}.compute.internal'
        ]

    return response


def error_response(error_type, error_message):
    return {
        'errorType': error_type,
        'errorMessage': error_message
    }


def set_logger(config):
    logging_level = config.get(bless_config.BLESS_OPTIONS_SECTION, bless_config.LOGGING_LEVEL_OPTION)
    numeric_level = getattr(logging, logging_level.upper(), None)
    if not isinstance(numeric_level, int):
        raise ValueError('Invalid log level: {}'.format(logging_level))

    logger = logging.getLogger()
    logger.setLevel(numeric_level)
    return logger


def check_entropy(config, logger):
    """
    Check the entropy pool and seed it with KMS if desired
    """
    region = os.environ['AWS_REGION']
    kms_client = boto3.client('kms', region_name=region)
    entropy_minimum_bits = config.getint(bless_config.BLESS_OPTIONS_SECTION, bless_config.ENTROPY_MINIMUM_BITS_OPTION)
    random_seed_bytes = config.getint(bless_config.BLESS_OPTIONS_SECTION, bless_config.RANDOM_SEED_BYTES_OPTION)

    with open('/proc/sys/kernel/random/entropy_avail', 'r') as f:
        entropy = int(f.read())
        logger.debug(entropy)
        if entropy < entropy_minimum_bits:
            logger.info(
                'System entropy was {}, which is lower than the entropy_'
                'minimum {}.  Using KMS to seed /dev/urandom'.format(
                    entropy, entropy_minimum_bits))
            response = kms_client.generate_random(
                NumberOfBytes=random_seed_bytes)
            random_seed = response['Plaintext']
            with open('/dev/urandom', 'w') as urandom:
                urandom.write(random_seed)


def setup_lambda_cache(ca_private_key_password, config_file):
    # For testing, ignore the static bless_cache, otherwise fill the cache one time.
    global global_bless_cache
    if ca_private_key_password is not None or config_file is not None:
        bless_cache = BlessLambdaCache(ca_private_key_password, config_file)
    elif global_bless_cache is None:
        global_bless_cache = BlessLambdaCache(config_file=os.path.join(os.getcwd(), 'bless_deploy.cfg'))
        bless_cache = global_bless_cache
    else:
        bless_cache = global_bless_cache
    return bless_cache


def validate_remote_usernames_agains_iam_groups(config: BlessConfig, request: BlessUserRequest):
    requested_remotes = request.remote_usernames.split(',')
    if config.getboolean(bless_config.BLESS_OPTIONS_SECTION,
                         bless_config.REMOTE_USERNAMES_AGAINST_IAM_GROUPS_OPTION):
        iam = boto3.client('iam')
        user_groups = iam.list_groups_for_user(UserName=request.bastion_user)

        group_name_template = config.get(bless_config.BLESS_OPTIONS_SECTION,
                                         bless_config.IAM_GROUP_NAME_VALIDATION_FORMAT_OPTION)
        for requested_remote in requested_remotes:
            required_group_name = group_name_template.format(requested_remote)

            user_is_in_group = any(
                group
                for group in user_groups['Groups']
                if group['GroupName'] == required_group_name
            )

            if not user_is_in_group:
                return error_response('ValidationError',
                                      'user {} is not in the {} iam group'.format(
                                          request.bastion_user,
                                          required_group_name))

    return None
