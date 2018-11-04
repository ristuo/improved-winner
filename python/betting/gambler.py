from datalayer.datalayer import load_existing_bets, load_bettable_predictions, get_db_connection
import pgutil
from pprint import pprint
from betting.agencies import BetConnector
from betting.bank import BankRoll
from datetime import datetime
import logging
import pandas as pd
ONE_NTH_KELLY = 4

class Gambler:
    def __init__(self, logger=None, make_bank=BankRoll, make_bet_connector=BetConnector):
        if logger is None:
            self.logger = logging.getLogger()
        else:
            self.logger = logger
        self.bet_connector = make_bet_connector(logger=self.logger)
        self.bank = make_bank(logger=self.logger)

    def get_bets(self):
        predictions = load_bettable_predictions()
        if predictions.shape[0] == 0:
            return []
        bettable, frozen = self.bank.get_balance()
        bankroll = bettable - frozen
        predictions['bet_time'] = datetime.now()
        bets = predictions[['game_id', 'model_name', 'probability', 'agency', 'sport_name', 'tournament',
                            'name', 'bet_time', 'bet_id', 'odds', 'outcome_id', 'kelly_bet']]
        renames = {
            'name': 'outcome_name',
            'id': 'outcome_id',
            'bet_id': 'agency_bet_id'
        }
        bets = bets.rename(
            index=str,
            columns=renames
        )
        bets = bets.to_dict('records')
        for bet in bets:
            bet['bet'] = round(bet.pop('kelly_bet') * bankroll / ONE_NTH_KELLY, 1)
            bet['bankroll'] = bankroll
            bankroll -= bet['bet']
        return bets

    def do_gamble(self):
        self.logger.info('Finding available profitable bets')
        bets = self.get_bets()
        if len(bets) == 0:
            self.logger.info('No profitable bets available, returning')
            return 0
        self.logger.info('Going to place ' + str(len(bets)) + ' bets')
        placed_bets = self.bet_connector.place_bets('veikkaus', bets)
        successful_bets = []
        for bet, response in zip(bets, placed_bets):
            if response['status'] == 'ACCEPTED':
                successful_bets += [bet]
        self.logger.info(str(len(successful_bets)) + ' bets were successful')
        if len(successful_bets) == 0:
            return 0
        conn = get_db_connection('betting')
        try:
            return pgutil.db.write_to_table(conn=conn, table_name='bets', logger=self.logger,
                                            dict_list=successful_bets)
        finally:
            conn.close()
