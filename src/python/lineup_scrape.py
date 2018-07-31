from selenium import webdriver
from pprint import pprint
import requests
from datetime import datetime
import os
import csv
import logging
import time
import random
import re
from bs4 import BeautifulSoup

import datetime
import time
import random
import logging

class VeikkausURLs:
    @staticmethod
    def get_game_url(game_id):
        return 'http://www.veikkausliiga.com/tilastot/2018/veikkausliiga/ottelut/{}/'.format(game_id)

    @staticmethod
    def get_lineup_url(game_id):
        return VeikkausURLs.get_game_url(game_id) + "/kokoonpanot"

    @staticmethod
    def get_ottelut_url(season):
        return 'http://www.veikkausliiga.com/tilastot/{}/veikkausliiga/ottelut/'.format(season)

def download_page(url, logger):
    logger.info("Downloading " + url)
    return requests.get(url)

def parse_player(element, player_position, team_type, game_id, logger):
    try:
        player_link = element.find('a')['href']
        player_id = re.search('/([0-9]+)/', player_link)
        return {
            'player_id': player_id.group(1),
            'player_position': player_position,
            'game_id': game_id,
            'team_type': team_type
        }
    except:
        logger.exception("Could not parse a player out of " + str(element))
        return None

def parse_players(team_element, classname, player_position, team_type, game_id, logger):
    players_raw = team_element.findAll('div', {'class': classname})
    if len(players_raw) == 0:
        logger.warning(
            "Failed to find player elements for game  " +
            game_id + " with class " + classname
        )
        return []
    logger.info("Found " + str(len(players_raw)) + " player elements for game " + game_id)
    res = [parse_player(x, player_position, team_type, game_id, logger) for x in players_raw]
    return [x for x in res if x is not None]

def load_lineup(team_element, team_type, game_id, logger):
    player_types = [
        ('player pos-puolustaja', 'puolustaja'),
        ('player pos-maalivahti', 'maalivahti'),
        ('player pos-keskikentta', 'keskikentta'),
        ('player pos-hyokkaaja', 'hyokkaaja')
    ]
    res = []
    for cn, pt in player_types:
        res += parse_players(team_element, cn, pt, team_type, game_id, logger)
    return res

def load_lineups(game_id, logger):
    game_id = str(game_id)
    try:
        url = VeikkausURLs.get_lineup_url(game_id)
        page = download_page(url, logger)
        soup = BeautifulSoup(page.content, 'html.parser')
        not_published = soup.findAll('div', {'class': 'not-published'})
        if len(not_published) > 0:
            logger.info("Information for game " + game_id + " not published yet, skipping!")
            return []
        logger.info("Parsing home team in game " + game_id)
        hometeam_element = soup.find('table', {'class': 'team-rosters home'})
        hometeam = load_lineup(hometeam_element, 'home', game_id, logger)
        awayteam_element = soup.find('table', {'class': 'team-rosters away'})
        awayteam = load_lineup(awayteam_element, 'away', game_id, logger)
        return hometeam + awayteam
    except:
        logger.exception("Failed to find lineups for game " + game_id)
        return []

def load_all_lineups(season, logger, max_dl = 5000, sleepy_time = 0.5):
    url = VeikkausURLs.get_ottelut_url(season)
    page = download_page(url, logger)
    soup = BeautifulSoup(page.content, 'html.parser')
    links = soup.findAll('a')
    game_ids = [l.group(1) for l in [re.search('ottelut/([0-9]+)/', x['href']) for x in links] if l is not None]
    game_ids = list(set(game_ids))
    res = []
    i = 1
    for game_id in game_ids:
        logger.info("Loading for game " + str(i) + "/" + str(len(game_ids)))
        res += load_lineups(game_id, logger)
        if i > max_dl:
            break
        i += 1
        logger.info("Sleeping for " + str(sleepy_time))
        time.sleep(sleepy_time)
    return res

def write_lineups(season, logger):
    lineups = load_all_lineups(season, logger)
    date_str = datetime.now().strftime('%Y-%m-%d')
    dirpath = "data/lineups/" + date_str
    os.makedirs(dirpath, exist_ok=True)
    outpath = dirpath + "/" + str(season) + ".csv"
    with open(outpath, 'w') as fp:
        writer = csv.DictWriter(fp, lineups[0].keys())
        writer.writeheader()
        for row in lineups:
            writer.writerow(row)

logger = logging.getLogger("Veikkausliiga scrape")
sh = logging.StreamHandler()
logger.setLevel(logging.INFO)
log_format = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
sh.setFormatter(log_format)
logger.addHandler(sh)

write_lineups(2017, logger)
write_lineups(2016, logger)
write_lineups(2015, logger)

