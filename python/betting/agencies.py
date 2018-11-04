from betting.veikkaus import VeikkausAPI


class BetConnector:
    def __init__(self, logger=None):
        self.agencies = {
            'veikkaus': VeikkausAPI(logger=logger)
        }

    def place_bets(self, agency, bets):
        if len(bets) > 25:
            raise RuntimeError('Place at most 25 bets at a time')
        if agency not in self.agencies:
            raise RuntimeError('Agency ' + agency + ' not available! Use one of ' +
                               ', '.join(list(self.agencies.keys())))
        api = self.agencies[agency]
        if not api.ready():
            api.connect()
        return api.do_bet(bets)

