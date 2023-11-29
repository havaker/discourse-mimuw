#!/usr/bin/env python
# Minimal setup.py file for packaging the main.py

from setuptools import setup, find_packages

setup(
    name='verify-login',
    packages=find_packages(),
    scripts=['main.py'],
)
