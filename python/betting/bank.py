from betting.veikkaus import VeikkausAPI
import logging


class BankRoll:
    def __init__(self, logger=None):
        if logger is None:
            self.logger = logging.getLogger()
        else:
            self.logger = logger
        self.veikkaus = VeikkausAPI(logger=self.logger)
        self.is_connected = False


    def get_balance(self):
        if not self.is_connected:
            self.veikkaus.connect()
            self.is_connected = True
        return self.veikkaus.get_balance()

