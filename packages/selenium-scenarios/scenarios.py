#!/usr/bin/env python
# Functions defined here uses Selenium to verify some scenarios against an
# existing Discourse server. They are intended to be used as a tests. Packaging
# with Nix makes it possible to expose them as a flake output -
# self.packages.x86_64-linux.selenium-scenarios. 

from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC

import utils

def verify_login():
    provider = utils.ArgumentsProvider('Verify login to Discourse server')
    # Make --server and --headless arguments available.
    provider.add_default_driver_arguments()
    # Expect the username to be passed as --username argument and password to
    # be set as $PASSWORD environment variable.
    provider.add_credentials()
    args = provider.parse()

    with utils.webdriver(args) as driver:
        # Open the Discourse login page
        driver.get(f'{args.address}/login')

        # Find the username and password input fields and enter the credentials
        username_field = driver.find_element(By.ID, 'login-account-name')
        username_field.send_keys(args.username)
        password_field = driver.find_element(By.ID, 'login-account-password')
        password_field.send_keys(args.password)

        # Submit the login form
        password_field.send_keys(Keys.RETURN)

        # Find the top-right user menu and verify that `username` is present in
        # its HTML.
        user = driver.find_element(By.ID, 'current-user')
        assert f'/u/{args.username}' in user.get_attribute('innerHTML')
