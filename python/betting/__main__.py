from betting.gambler import Gambler
from misc.util import get_logger

logger = get_logger(lvl='DEBUG', name='Betting')
gambler = Gambler(logger=logger)
gambler.do_gamble()
