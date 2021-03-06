![alt text](bless_logo.png "BLESS")
# BLESS - Bastion's Lambda Ephemeral SSH Service

BLESS is an SSH Certificate Authority that runs as an AWS Lambda function and is used to sign SSH
public keys.

SSH Certificates are an excellent way to authorize users to access a particular SSH host,
as they can be restricted for a single use case, and can be short lived.  Instead of managing the
authorized_keys of a host, or controlling who has access to SSH Private Keys, hosts just
need to be configured to trust an SSH CA.

BLESS should be run as an AWS Lambda in an isolated AWS account.  Because BLESS needs access to a
private key which is trusted by your hosts, an isolated AWS account helps restrict who can access
that private key, or modify the BLESS code you are running.

AWS Lambda functions can use an AWS IAM Policy to limit which IAM Roles can invoke the Lambda
Function.  If properly configured, you can restrict which IAM Roles can request SSH Certificates.
For example, your SSH Bastion (aka SSH Jump Host) can run with the only IAM Role with access to
invoke a BLESS Lambda Function configured with the SSH CA key trusted by the instances accessible
to that SSH Bastion.

## Getting Started
These instructions are to get BLESS up and running in your local development environment.
### Installation Instructions
Clone the repo:

    $ git clone git@github.com:Netflix/bless.git

Cd to the bless repo:

    $ cd bless

Create a virtualenv if you haven't already:

    $ python3.7 -m venv venv

Activate the venv:

    $ source venv/bin/activate

Install package and test dependencies:

    (venv) $ make develop

Run the tests:

    (venv) $ make test


## Deployment
To deploy an AWS Lambda Function, you need to provide a .zip with the code and all dependencies.
The .zip must contain your lambda code and configurations at the top level of the .zip.  The BLESS
Makefile includes a publish target to package up everything into a deploy-able .zip if they are in
the expected locations.  You will need to setup your own Python 3.7 lambda to deploy the .zip to.

Use `bless_lambda.lambda_handler` to issue user or host certificates depending on the payload contents.

### Compiling BLESS Lambda Dependencies
To deploy code as a Lambda Function, you need to package up all of the dependencies.  You will need to
compile and include your dependencies before you can publish a working AWS Lambda.

BLESS uses a docker container running [Amazon Linux 2](https://hub.docker.com/_/amazonlinux) to package everything up:
- Execute ```make lambda-deps``` and this will run a container and save all the dependencies in ./aws_lambda_libs

### Protecting the CA Private Key
- Generate a password protected RSA Private Key in the PEM format:
```shell
$ ssh-keygen -t rsa -b 4096 -m PEM -f KEY_NAME -C "SSH CA Key"
```
- **Note:** OpenSSH Private Key format is not supported.
- **Note2:** With `awscli` v2 use `--cli-binary-format raw-in-base64-out` flag in all commands (https://docs.aws.amazon.com/cli/latest/userguide/cliv2-migration.html#cliv2-migration-binaryparam)
- Use KMS to encrypt your password.  You will need a KMS key per region, and you will need to
encrypt your password for each region. You can use the AWS CLI like this:
```shell
$ REGION=eu-west-1
$ aws kms create-alias \
            --region $REGION \
            --alias-name alias/YOUR_KMS_KEY \
            --target-key-id $(aws kms create-key --region $REGION | jq -r .KeyMetadata.KeyId)

$ aws kms encrypt \
    --key-id $(aws kms describe-key --region $REGION --key-id alias/bless | jq -r .KeyMetadata.KeyId) \
    --plaintext <YOUR_CA_KEY_PASSWORD_IN_PLAINTEXT> \
    --region $REGION | jq -r .CiphertextBlob
```

- Manage your Private Keys .pem files and passwords outside of this repo.
- Update your bless_deploy.cfg with your Private Key's filename and encrypted passwords.
- Provide your desired ./lambda_configs/ca_key_name.pem prior to Publishing a new Lambda .zip
- Set the permissions of ./lambda_configs/ca_key_name.pem to 444.

You can now provide your private key and/or encrypted private key password via the lambda environment or config file.
In the `[Bless CA]` section, you can set `ca_private_key` instead of the `ca_private_key_file` with a base64 encoded
version of your .pem (e.g. `cat key.pem | base64` ).

Because every config file option is supported in the environment, you can also just set `bless_ca_default_password`
and/or `bless_ca_ca_private_key`.  Due to limits on AWS Lambda environment variables, you'll need to compress RSA 4096
private keys, which you can now do by setting `bless_ca_ca_private_key_compression`. For example, set 
`bless_ca_ca_private_key_compression = bz2` and `bless_ca_ca_private_key` to the output of 
`cat ca-key.pem | bzip2 | base64`.

### BLESS Config File
- Refer to the the [Example BLESS Config File](bless/config/bless_deploy_example.cfg) and its
included documentation.
- Manage your bless_deploy.cfg files outside of this repo.
- Provide your desired `./lambda_configs/bless_deploy.cfg` prior to Publishing a new Lambda .zip
- The required [Bless CA] option values must be set for your environment.
- Every option can be changed in the environment. The environment variable name is constructed
as section_name_option_name (all lowercase, spaces replaced with underscores).

### Publish Lambda .zip
- Provide your desired `./lambda_configs/KEY_NAME` prior to Publishing
- Provide your desired [BLESS Config File](bless/config/bless_deploy_example.cfg) at
./lambda_configs/bless_deploy.cfg prior to Publishing
- Provide the [compiled dependencies](#compiling-bless-lambda-dependencies) at ./aws_lambda_libs
- run:
```shell
(venv) $ make publish
```

- deploy ./publish/bless_lambda.zip to AWS via the AWS Console,
[AWS SDK](http://boto3.readthedocs.io/en/latest/reference/services/lambda.html), or
[S3](https://aws.amazon.com/blogs/compute/new-deployment-options-for-aws-lambda/)
- remember to deploy it to all regions.
```shell
$ aws lambda update-function-code --function-name LAMBDA_NAME --zip-file fileb://$(pwd)/publish/bless_lambda.zip
```


### Lambda Requirements
You should deploy this function into its own AWS account to limit who has access to modify the
code, configs, or IAM Policies.  An isolated account also limits who has access to the KMS keys
used to protect the SSH CA Key.

The BLESS Lambda function should run as its own IAM Role and will need access to an AWS KMS Key in
each region where the function is deployed.  The BLESS IAMRole will also need permissions to obtain
random from kms (kms:GenerateRandom) and permissions for logging to CloudWatch Logs
(logs:CreateLogGroup,logs:CreateLogStream,logs:PutLogEvents).

## Using BLESS
After you have [deployed BLESS](#deployment) you can run the sample [BLESS Client](bless_client/bless_client.py)
from a system with access to the required [AWS Credentials](http://boto3.readthedocs.io/en/latest/guide/configuration.html).
This client is really just a proof of concept to validate that you have a functional lambda being called with valid
IAM credentials. 

Using the python script:

    (venv) $ ./bless_client.py region lambda_function_name bastion_user remote_usernames <id_rsa.pub to sign> <output id_rsa-cert.pub> [kmsauth] [bastion_user_ip] [bastion_source_ip]

Using the shell script (preferred):
```shell
$ ./bless-client.sh REGION LAMBDA_NAME REMOTE_USERNAMES_COMMA_SEPARATED PUB_KEY_PATH
```

## Verifying Certificates
You can inspect the contents of a certificate with ssh-keygen directly:

    $ ssh-keygen -L -f your-cert.pub
    
## setup cert-authority in clients

```shell
$ REGION=eu-west-1
$ echo "@cert-authority *.$REGION.compute.amazonaws.com $(cat /path/to/downloaded/CA_KEY_NAME.pub)" > ~/.ssh/known_hosts
```

## Enabling BLESS Certificates On Servers
Using `bless_client\bless_client_host_inside_instance.py` inside the ssh host will sign the host key
ant output it into `/etc/ssh/ssh_host_rsa_key-cert.pub`

Add the following line to `/etc/ssh/sshd_config`:

    TrustedUserCAKeys /etc/ssh/KEY_NAME.pub
    # optional
    HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub

Add a new file, owned by and only writable by root, at `/etc/ssh/CA_KEY_NAME.pub` with the contents:

    ssh-rsa AAAAB3NzaC1yc2EAAAADAQ…  #id_rsa.pub of an SSH CA
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQ…  #id_rsa.pub of an offline SSH CA
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQ…  #id_rsa.pub of an offline SSH CA 2

To simplify SSH CA Key rotation you should provision multiple CA Keys, and leave them offline until
you are ready to rotate them.

Additional information about the TrustedUserCAKeys file is [here](https://www.freebsd.org/cgi/man.cgi?query=sshd_config)

## Project resources
- Source code <https://github.com/netflix/bless>
- Issue tracker <https://github.com/netflix/bless/issues>
- Step by step: <https://medium.com/swlh/run-netflix-bless-ssh-certificate-authority-in-aws-lambda-f507a620e42>

## Manual steps to sign SSH keys with CA
https://gist.github.com/asrath/f9c7a827b4829c24bef316dca6c28299
