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

    def parse(self):
        args = self.parser.parse_args()

        args.password = os.environ.get('PASSWORD')
        if hasattr(args, 'username') and not args.password:
            print('Please set PASSWORD environment variable')
            sys.exit(1)

        return args

@contextlib.contextmanager
def webdriver(args):
    options = Options()
    if args.headless:
        options.add_argument("--headless")

    driver = Firefox(options)
    # Wait up to 10 seconds for elements to appear
    driver.implicitly_wait(10)
    try:
        yield driver
    finally:
        driver.quit()


