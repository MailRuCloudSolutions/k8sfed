#!/usr/bin/env python3

"""Client to handle connections and actions executed against a remote host."""

import argparse
import codecs
import sys
import time
from functools import wraps
from os import system
from paramiko import SSHClient, AutoAddPolicy, RSAKey
from paramiko.auth_handler import AuthenticationException, SSHException
from scp import SCPClient, SCPException


sys.stdout = codecs.getwriter("utf-8")(sys.stdout.detach())
sys.stderr = codecs.getwriter("utf-8")(sys.stderr.detach())


class Logger:
    def info(self, msg):
        sys.stdout.write(msg + '\n')

    def error(self, msg):
        sys.stderr.write(msg + '\n')


logger = Logger()


def retry(ExceptionToCheck, tries=3, delay=2, backoff=2, logger=None):
    def deco_retry(f):
        @wraps(f)
        def f_retry(*args, **kwargs):
            mtries, mdelay = tries, delay
            while mtries > 1:
                try:
                    return f(*args, **kwargs)
                except ExceptionToCheck as e:
                    msg = "%s, Retrying in %d seconds..." % (str(e), mdelay)
                    if logger:
                        logger.info(msg)
                    time.sleep(mdelay)
                    mtries -= 1
                    mdelay *= backoff
            return f(*args, **kwargs)
        return f_retry
    return deco_retry


class RemoteClient:
    """Client to interact with a remote host via SSH & SCP."""

    def __init__(self, host, user, ssh_key_filepath, remote_path):
        self.host = host
        self.user = user
        self.ssh_key_filepath = ssh_key_filepath
        self.remote_path = remote_path
        self.client = None
        self.scp = None
        self.conn = None

    def __connect(self):
        """
        Open connection to remote host.
        """
        try:
            self.client = SSHClient()
            self.client.load_system_host_keys()
            self.client.set_missing_host_key_policy(AutoAddPolicy())
            self.client.connect(self.host,
                                username=self.user,
                                key_filename=self.ssh_key_filepath,
                                look_for_keys=True,
                                timeout=5000)
            self.scp = SCPClient(self.client.get_transport())
        except AuthenticationException as error:
            logger.info('Authentication failed: did you remember to create an SSH key?')
            logger.error(error)
            raise error
        finally:
            return self.client

    def __disconnect(self):
        self.client.close()
        self.scp.close()
        self.client = None

    def upload_file(self, file, remote_path=None):
        """Upload a single file to a remote directory."""
        if self.client is None:
            self.client = self.__connect()
        if not remote_path:
            remote_path = self.remote_path
        try:
            self.scp.put(file,
                         recursive=True,
                         remote_path=remote_path)
        except SCPException as error:
            logger.error(error)
            raise error
        finally:
            logger.info(f'Uploaded {file} to {self.remote_path}')
            self.__disconnect()

    @retry(Exception, logger=logger)
    def execute_command(self, cmd):
        """
        Execute command in ssh session.

        :param cmd: unix command as string.
        """
        if self.client is None:
            self.client = self.__connect()
        try:
            stdin, stdout, stderr = self.client.exec_command(cmd)
            stdout.channel.recv_exit_status()
            response = stdout.readlines()
            error = stderr.readlines()
            if response or error:
                msg = f'INPUT: {cmd}\n'
                if response:
                    msg += 'STDOUT:\n{}'.format('\n'.join(response))
                if error:
                    msg += 'STDERR:\n{}'.format('\n'.join(error))
                logger.info(msg)
        except Exception:
            self.__disconnect()
            raise
        else:
            self.__disconnect()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True,
                        help='Remote host to connect by SSH')
    parser.add_argument('--user', required=True,
                        help='User to connect to remote host')
    parser.add_argument('--private-key', required=True,
                        help='SSH private key')
    parser.add_argument('--remote-path', required=True,
                        help='Remote path on SSH connection')

    args = parser.parse_args()
    rc = RemoteClient(args.host, args.user, args.private_key, args.remote_path)
    rc.execute_command('mkdir -p .aws && mkdir -p .kube')
    rc.execute_command(
        'curl -sLO {} && chmod 755 kubectl && sudo mv -v kubectl /usr/bin/'.format(
            'https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/linux/amd64/kubectl'
        )
    )
    rc.execute_command(
        'curl -sLO {} && tar xzf kubefedctl-0.1.0-rc6-linux-amd64.tgz && chmod 755 kubefedctl && sudo mv -v kubefedctl /usr/bin/'.format(
            'https://github.com/kubernetes-sigs/kubefed/releases/download/v0.1.0-rc6/kubefedctl-0.1.0-rc6-linux-amd64.tgz'
        )
    )
    rc.execute_command(
        'curl -sL {} -o jq && chmod 755 jq && sudo mv -v jq /usr/bin/'.format(
            'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64'
        )
    )
    rc.execute_command(
        'curl -sO https://bootstrap.pypa.io/get-pip.py && sudo python get-pip.py'
    )
    rc.execute_command('sudo pip install -q awscli')
    rc.upload_file(['/root/.aws/config', '/root/.aws/credentials'], '/home/centos/.aws/')
    rc.upload_file('/root/.kube/config', '/home/centos/.kube/')
    kubefedctl_cmd = (
        "export AWSCTX=$(kubectl config view -o json | jq -c '.contexts[] | select (.name | contains(\"awsfed\")) | .name' | jq -r .) && "
        "export AWSNAME=$(kubectl config view -o json | jq -c '.clusters[] | select (.name | contains(\"awsfed\")) | .name' | jq -r .) && "
        "export MCSCTX=$(kubectl config view -o json | jq -c '.contexts[] | select (.name | contains(\"mcs-cluster\")) | .name' | jq -r .) && "
        "export MCSNAME=$(kubectl config view -o json | jq -c '.clusters[] | select (.name | contains(\"mcs-cluster\")) | .name' | jq -r .) && "
        "kubefedctl join $AWSNAME --cluster-context $AWSCTX  --host-cluster-context $AWSCTX --v=2 && "
        "kubefedctl join $MCSNAME --cluster-context $MCSCTX  --host-cluster-context $AWSCTX --v=2"
    )
    rc.execute_command(kubefedctl_cmd)
    rc.execute_command('rm -rf .aws && rm -rf .kube')


if __name__ == '__main__':
    main()
