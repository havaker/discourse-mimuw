#!/usr/bin/env python
# Functions defined here uses Selenium to verify some scenarios against an
# existing Discourse server. They are intended to be used as a tests. Packaging
# with Nix makes it possible to expose them as a flake output -
# self.packages.x86_64-linux.selenium-scenarios. 

import time
import json
import re

import requests

from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# Local module ./utils.py
import utils

TIMEOUT_SECONDS = 10

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
        print("Opening the Discourse login page.")
        driver.get(f'{args.address}/login')

        print("Filling in the login form.")
        # Find the username and password input fields and enter the credentials
        username_field = driver.find_element(By.ID, 'login-account-name')
        username_field.send_keys(args.username)
        password_field = driver.find_element(By.ID, 'login-account-password')
        password_field.send_keys(args.password)

        print("Submitting the login form.")
        # Submit the login form
        password_field.send_keys(Keys.RETURN)

        print("Verifying that the user is logged in.")
        # Find the top-right user menu and verify that `username` is present in
        # its HTML.
        user = driver.find_element(By.ID, 'current-user')
        assert f'/u/{args.username}' in user.get_attribute('innerHTML')

def registration():
    provider = utils.ArgumentsProvider('Attempt to register a new user')
    # Make --server and --headless arguments available.
    provider.add_default_driver_arguments()
    # Expect the username to be passed as --username argument and password to
    # be set as $PASSWORD environment variable.
    provider.add_credentials()
    # Expect the email to be passed as --email argument
    provider.add_email()
    # Expect the full name to be passed as --name argument
    provider.add_full_name()
    # Expect the MailHog address to be passed as --mailhog-address argument
    provider.add_mailhog()
    args = provider.parse()

    with utils.webdriver(args, implicit_wait_seconds=None) as driver:
        # Helper function to wait until a condition is met.
        def wait_until(expected_condition):
            return WebDriverWait(driver, TIMEOUT_SECONDS).until(expected_condition)

        print("Opening the Discourse page.")
        driver.get(args.address)

        print("Clicking the Sign Up button.")
        signup_button = driver.find_element(By.CLASS_NAME, 'sign-up-button')
        signup_button.click()

        print("Filling in the registration form.")
        # Find registration form elements and enter credentials
        email_field = wait_until(EC.presence_of_element_located((By.ID, 'new-account-email')))
        email_field.send_keys(args.email)

        username_field = wait_until(EC.presence_of_element_located((By.ID, 'new-account-username')))
        username_field.send_keys(args.username)

        name_field = wait_until(EC.presence_of_element_located((By.ID, 'new-account-name')))
        name_field.send_keys(args.name)

        password_field = wait_until(EC.presence_of_element_located((By.ID, 'new-account-password')))
        password_field.send_keys(args.password)

        print("Slamming the RETURN key.")
        # Submit the registration form. To mitigate timing issues, smash the
        # RETURN key a few times (until the page changes).
        for _ in range(TIMEOUT_SECONDS):
            try:
                password_field.click()
                password_field.send_keys(Keys.RETURN)
            except Exception as e:
                if not 'stale' in str(e):
                    throw(e)

            if driver.current_url != args.address:
                break

            # Wait before trying again.
            time.sleep(1)
        else:
            html_content = driver.page_source
            print(html_content)
            print(f"\nTimed out waiting for registration to complete")
            return 1

        # Use MailHog API to get the activation email.
        # To mitigate timing issues, poll the API until the activation email
        # is received.
        print("Extracting the email with an activation link from the MailHog API.")
        messages_url = f"{args.mailhog_address}/api/v2/messages"
        poll_interval_seconds = 0.5

        max_poll_attempts = int(TIMEOUT_SECONDS / poll_interval_seconds)
        for _ in range(max_poll_attempts):
            response = requests.get(messages_url)
            messages = response.json()

            if messages['count'] > 0:
                latest_message = messages['items'][0]
                to_address = latest_message['Content']['Headers']['To']
                if args.email in to_address:
                    break  # Exit the loop if the latest message is addressed to `args.email`.

            # Wait before polling again.
            time.sleep(poll_interval_seconds)
        else:
            html_content = driver.page_source
            print(html_content)
            print(f"Timed out waiting for an email addressed to {args.email}")
            return 1

        # Rock solid email parsing:
        email_content = json.dumps(latest_message) # ;))
        assert 'account already exists for' not in email_content
        regex = r'({}u/activate-account/[0-9a-zA-Z]*)\\"'.format(re.escape(args.address))
        activation_link = re.search(regex, email_content).group(1)

        print("Visiting the activation link.")
        driver.get(activation_link)

        print("Activating the account.")
        activate = wait_until(EC.presence_of_element_located((By.ID, 'activate-account-button')))
        activate.click()
        # Allow for the possibility that the activation button is not longer visible.
        try:
            activate.send_keys(Keys.RETURN)
        except Exception:
            pass

        # Wait until the redirect to the Discourse homepage is complete.
        def was_redirected_to_homepage(driver):
            if 'manually approve' in driver.page_source:
                raise Exception("Registration requires manual approval")
            return driver.current_url == args.address
        # Using the above function enables us to detect if the registration
        # requires manual approval and fail if it does without waiting the full
        # TIMEOUT_SECONDS seconds.
        wait_until(was_redirected_to_homepage)

        print("Verifying that the user is logged in.")
        # Find the top-right user menu and verify that `username` is present in
        # its HTML.
        user = wait_until(EC.presence_of_element_located((By.ID, 'current-user')))
        assert f'/u/{args.username}' in user.get_attribute('innerHTML')

        print("Success!")
        # Exit code 0 means success.
        return 0
