import argparse
import contextlib
import os
import sys

from selenium.webdriver import Firefox
from selenium.webdriver.firefox.options import Options

class ArgumentsProvider:
    def __init__(self, description):
        self.parser = argparse.ArgumentParser(description=description)

    def add_default_driver_arguments(self):
        self.parser.add_argument('--headless', action='store_true')
        self.parser.add_argument('--address',
                                 help='Discourse server address',
                                 default='http://server')

    # Expect password to be set as environment variable & username to be passed
    # as command line argument.
    def add_credentials(self):
        self.parser.add_argument('--username', default='balenciaga')

    def add_email(self):
        self.parser.add_argument('--email', default='jkjk694202137@students.mimuw.edu.pl')

    def add_full_name(self):
        self.parser.add_argument('--name', default='Jan Kowalski')

    def add_mailhog(self):
        self.parser.add_argument('--mailhog-address', default='http://server:8025')

    def parse(self):
        args = self.parser.parse_args()

        # If trailing slash is not present, add it.
        if not args.address.endswith('/'):
            args.address += '/'

        args.password = os.environ.get('PASSWORD')
        if hasattr(args, 'username') and not args.password:
            print('Please set PASSWORD environment variable')
            sys.exit(1)

        return args

@contextlib.contextmanager
def webdriver(args, implicit_wait_seconds=10):
    options = Options()
    if args.headless:
        options.add_argument("--headless")

    driver = Firefox(options)

    if implicit_wait_seconds is not None:
        # Wait up to `implicit_wait_seconds` for elements to appear.
        driver.implicitly_wait(implicit_wait_seconds)

    try:
        yield driver
    finally:
        driver.quit()


