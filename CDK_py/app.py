#!/usr/bin/env python3

from aws_cdk import core

from cdk_py.cdk_py_stack import CdkPyStack


app = core.App()
CdkPyStack(app, "cdk-py",env={'region': 'eu-west-2'})

app.synth()
