import requests
import json
import logging
from pprint import pprint
import os
import json
class VeikkausAPI:
    headers = {
        'Content-type': 'application/json',
        'Accept': 'application/json',
        'X-ESA-APi-Key': 'ROBOT'
    }
    host = 'https://www.veikkaus.fi'

    def __init__(self, logger=None):
        self.username = None
        self.password = None
        if logger is None:
            self.logger = logging.getLogger()
        else:
            self.logger = logger
        self.session = None

    def connect(self, username = None, password = None):
        if username is None:
            self.logger.debug('Loading username from env')
            self.username = os.environ['VEIKKAUS_USERNAME']
        else:
            self.username = username
        if password is None:
            self.logger.debug('Loading password from env')
            self.password = os.environ['VEIKKAUS_PASSWORD']
        else:
            self.password = password
        self.session = self._login()

    def _login(self):
        s = requests.Session()
        login_req = {
            "type": "STANDARD_LOGIN",
            "login": self.username,
            "password": self.password
        }
        r = s.post(
            self.host + '/api/bff/v1/sessions',
            verify=True,
            data=json.dumps(login_req),
            headers=VeikkausAPI.headers)
        if r.status_code == 200:
            return s
        else:
            msg = "Authentication failed", r.status_code
            self.logger.error(msg)
            raise Exception(msg)

    def _check_init(self):
        if self.session is None:
            raise RuntimeError(
                'Use connect() to establish session before running commands')

    def get_balance(self):
        self._check_init()
        r = self.session.get(VeikkausAPI.host + "/api/v1/players/self/account",
                             verify=True, headers=VeikkausAPI.headers)
        r.raise_for_status()
        j = r.json()
        return (
            float(j["balances"]["CASH"]["balance"])/100,
            float(j["balances"]["CASH"]["frozenBalance"])/100)

    @staticmethod
    def _create_ebet_bet(bet_amount, game_id, odds, result):
        return [
           {
              "selections": [
                 {
                    "stake": round(bet_amount * 100),
                    "competitors": {
                       "main": [
                            str(result)
                       ],
                       'spare': [
                            str(round(odds * 100))
                        ]
                    },
                    "systemBetType": "NORMAL",
                    "rowId": game_id
                 },
              ],
              "type": "NORMAL",
              "requestId": "request-14",
              "gameName": "EBET"
           }
        ]

    def ready(self):
        return self.session is not None

    def _place_bet(self, bet_payload):
        self.logger.info('Posting bets to Veikkaus')
        r = self.session.post(
            VeikkausAPI.host + "/api/v1/sport-games/wagers",
            verify=True,
            data=json.dumps(bet_payload), headers=VeikkausAPI.headers)
        try:
            r.raise_for_status()
            for x in r:
                if x['STATUS'] != 'ACCEPTED':
                    self.logger.warning(r.text)
        except:
            self.logger.error(r.text)
        return r

    def do_bet(self, bets):
        self._check_init()
        bet_payload = []
        for bet in bets:
            self.logger.debug('Adding bet ' + str(bet))
            payload = VeikkausAPI._create_ebet_bet(
                bet_amount=bet['bet'],
                game_id=bet['agency_bet_id'],
                odds=bet['odds'], result=bet['outcome_id'])
            self.logger.debug('Bet payload towards Veikkaus is ' + str(payload))
            bet_payload += payload
        res = self._place_bet(bet_payload)
        return json.loads(res.text)
