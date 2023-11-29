#!/usr/bin/env python
# This script uses Selenium to verify that a user can log in to a Discourse
# server. It is intended to be used as a test. It is packaged with Nix and made
# available as a flake output - self.packages.x86_64-linux.verify-login.
# Uses environment variables for credentials, arguments for server address and
# headless mode.

import os
import sys
import argparse

from selenium import webdriver
from selenium.webdriver.firefox.options import Options

from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

parser = argparse.ArgumentParser(description='Discourse login verification')
parser.add_argument('address', help='Discourse server address', default='http://server')
parser.add_argument('--headless', action='store_true')
args = parser.parse_args()

username = os.environ.get('DISCOURSE_USERNAME')
password = os.environ.get('DISCOURSE_PASSWORD')
if not username or not password:
    print('Please set DISCOURSE_USERNAME and DISCOURSE_PASSWORD environment variables')
    sys.exit(1)

options = Options()
if args.headless:
    options.add_argument("--headless")
driver = webdriver.Firefox(options)

try:
    # Open the Discourse login page
    driver.get(f'{args.address}/login')

    # Find the username and password input fields and enter the credentials
    username_field = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, 'login-account-name'))
    )
    username_field.send_keys(username)

    password_field = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, 'login-account-password'))
    )
    password_field.send_keys(password)

    # Submit the login form
    password_field.send_keys(Keys.RETURN)

    # Wait for the login process to complete
    user = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, 'current-user'))
    )

    # verify that `username` is present in the HTML of `user`
    assert f'/u/{username}' in user.get_attribute('innerHTML')

finally:
    # Close the browser window
    driver.quit()

