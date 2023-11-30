#!/usr/bin/env python
# Minimal setup.py file for packaging the scenarios.py

from setuptools import setup, find_packages

setup(
    name='selenium-scenarios',
    packages=find_packages(),
    py_modules=['scenarios', 'utils'],
    entry_points={
        'console_scripts': [
            'verify-login = scenarios:verify_login'
        ]
    },
)
