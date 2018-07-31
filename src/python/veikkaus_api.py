import requests
import os.path
from time import sleep
from csv import DictWriter
from datetime import datetime
import pprint
import logging
import json
from pprint import pprint
datetime.fromtimestamp(1532228400000/1000)
BASIC_HEADERS = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-ESA-API-Key': 'ROBOT'
}
SLEEPY_TIME = 0.25

def _parse_dtm(stampy):
    return datetime.fromtimestamp(float(stampy)/1000)

class GameOdds:
    def __init__(self, short_name, open_time, close_time, name, time, sport_name, tournament_name, category_name, odds,
                 dl_time, event_id, event_name):
        self.short_name = short_name
        self.event_id = event_id
        self.event_name = event_name
        self.close_time = close_time
        self.open_time = open_time
        self.name = name
        self.time = time
        self.sport_name = sport_name
        self.tournament_name = tournament_name
        self.category_name = category_name
        self.odds = odds
        self.dl_time = dl_time

    def to_dictionary(self):
        res = self.__dict__.copy()
        res.pop('odds')
        odds_dict = {}
        for odd in self.odds:
            name = "bet_" + odd['id']
            odds_dict[name + '_odds'] = odd['odds']
            odds_dict[name + '_status'] = odd['status']
            odds_dict[name + '_name'] = odd['name']
        return {**res, **odds_dict}

    def to_dictionaries(self):
        game_dict = self.__dict__.copy()
        game_dict.pop('odds')
        res = []
        for odd in self.odds:
            res.append({**game_dict, **odd})
        return res

def _do_dl(logger, url, headers):
    logger.info('About to query ' + url)
    logger.info('Sleeping for {}'.format(SLEEPY_TIME))
    sleep(SLEEPY_TIME)
    r = requests.get(url, headers = headers)
    r.raise_for_status()
    try:
        res = json.loads(r.text)
    except:
        logger.exception("Failed to parse JSON")
    return res

def _download_games(logger, game_names = 'EBET'):
    url = 'https://www.veikkaus.fi/api/v1/sport-games/draws?game-names={}'.format(game_names)
    return _do_dl(logger, url, BASIC_HEADERS)

def get_games(logger, game_names = 'EBET'):
    games = _download_games(logger, game_names)['draws']
    return _parse_games(logger, games, datetime.now())


def _download_event_sport(logger, event_id):
    url = 'https://www.veikkaus.fi/api/v1/sports/events/{}?lang=fi'.format(event_id)
    headers = {**BASIC_HEADERS, **{'Accept-Encoding': 'gzip, deflate'}}
    return _do_dl(logger, url, headers)

def _parse_games(logger, games, dl_time):
    res = []
    i = 1
    logger.info("Fetched " + str(len(games)) + " games, starting to parse.")
    for game in games:
        gid = str(i) + "/" + str(len(games))
        logger.info("Trying to parse game " + gid)
        i += 1
        try:
            open_time = _parse_dtm(game['openTime'])
            close_time = _parse_dtm(game['closeTime'])
            game_name = game['gameName']
            for row in game['rows']:
                try:
                    event_id = row['eventId']
                except:
                    logger.error('No event ID found for row' + str(row) + " on game " + gid)
                    continue
                short_name = row['shortName']
                meta = _download_event_sport(logger, event_id)
                sport_name = meta['sportName']
                event_name = meta['name']
                time = _parse_dtm(meta['date'])
                category_name = meta['categoryName']
                tournament_name = meta['tournamentName']
                odds = []
                for competitor in row['competitors']:
                    if 'odds' in competitor:
                        odds.append({
                            'name': competitor['name'],
                            'odds': float(competitor['odds']['odds']) / 100,
                            'status': competitor['status'],
                            'id': competitor['id']
                        })
            game_odds = GameOdds(
                name = game_name,
                event_id = event_id,
                short_name = short_name,
                sport_name = sport_name,
                event_name = event_name,
                open_time = open_time,
                close_time = close_time,
                dl_time = dl_time,
                time = time,
                category_name = category_name,
                tournament_name = tournament_name,
                odds = odds
            )
            logger.info("Successfully parsed game " + gid)
            res.append(game_odds)
        except:
            logger.error("Error in parsing a game " + gid)

    return res

def save_games_as_csv(games, filepath = "games.csv", overwrite = False):
    if not overwrite:
        if os.path.exists(filepath):
            writemode = "a"
            write_header = False
        else:
            writemode = "w"
            write_header = True
    else:
        writemode = "w"
        write_header = True
    with open(filepath, writemode) as fp:
        writer = DictWriter(fp, games[0].to_dictionaries()[0].keys())
        if write_header:
            writer.writeheader()
        for game in games:
            for d in game.to_dictionaries():
                writer.writerow(d)


logger = logging.getLogger("Veikkaus API logger")
sh = logging.StreamHandler()
logger.setLevel(logging.INFO)
log_format = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
sh.setFormatter(log_format)
logger.addHandler(sh)
games = get_games(logger)
dirpath = 'data/odds/{}'.format(datetime.now().strftime("%Y-%m-%d"))
os.makedirs(dirpath, exist_ok=True)
save_games_as_csv(games, dirpath + "/games.csv", overwrite = False)
