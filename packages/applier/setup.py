#!/usr/bin/env python

# For more informations on what is going on here check out ../selenium-scenarios/setup.py.

from setuptools import setup, find_packages

setup(
    name='applier',
    packages=find_packages(),
    py_modules=['main'],
    entry_points={
        'console_scripts': [
            'applier = main:apply',
            'user-in-group = main:assert_user_in_group',
        ]
    },
)
