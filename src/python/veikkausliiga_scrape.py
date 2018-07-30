from selenium import webdriver
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
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException


GOAL_EVENTS = set([
    'Kulmapotku',
    'Laukaus',
    'Laukaus ohi',
    'Syöttö',
    'Vapaapotku',
    'Rangaistuspotku'
])

class Game:
    def __init__(self, home_team, away_team, name, date, time, home_team_goals,
                 away_team_goals, events = None):
        self.name = name
        self.home_team = home_team
        self.away_team = away_team
        self.date = date
        self.time = time
        self.home_team_goals = home_team_goals
        self.away_team_goals = away_team_goals
        self.events = events


    def __str__(self):
        return self.name

    @staticmethod
    def from_dict(game_dict):
        name = game_dict['Ottelu']
        home_team, away_team = name.split(' - ')
        time = game_dict['Aika']
        date = game_dict['Pvm']
        home_team_goals, away_team_goals = [int(i) for i in game_dict['Tulos'].split(' — ')]
        return Game(
            home_team = home_team,
            away_team = away_team,
            name = name,
            date = date,
            time = time,
            home_team_goals = home_team_goals,
            away_team_goals=away_team_goals
        )



class Event:
    @staticmethod
    def _parse_minute(text):
        res = [int(i) for i in text.strip().replace("'", "").split(' + ')]
        is_additional_time = len(res) > 1
        if len(res) > 2:
            raise RuntimeError("Failed to parse " + text + " to minutes!")
        return (sum(res), is_additional_time)

    def __init__(self, event_type, player_number,
                 is_additional_time, player_link, team, minutes, home_team, away_team,
                 date, extra_info = ""):
        self.event_type = event_type
        self.player_number = player_number
        self.extra_info = extra_info
        self.player_link = player_link
        self.team = team
        self.home_team = home_team
        self.away_team = away_team
        self.date = date
        self.is_additional_time = is_additional_time
        self.minutes = minutes

    def __str__(self):
        return str(self.minutes) + ", "+ self.event_type + ": " + self.player_number + " " + self.team

    @staticmethod
    def is_goal(event_type):
        return re.search("[0-9]–[0-9]$", event_type) is not None

    @staticmethod
    def from_bs(elem, home_team, away_team, date):
        minutes, is_additional_time = Event._parse_minute(elem.find('td', {'class': 'time'}).text)
        team = elem.find('span', {'class': 'front'}).text
        player_link = elem.find('a')['href']
        event_type = elem.find('span', {'class': 'event'}).text.split(",")[0].replace(",", "")
        if Event.is_goal(event_type):
            event_type = "Maali"
        try:
            extra_info = elem.find('span', {'class': 'booking'}).find('a').text
        except:
            extra_info = ""
        try:
            player_number = re.search('#[0-9]+', elem.find('span', {'class': 'event'}).text).group()
        except:
            player_number = "?"
        return Event(
            event_type = event_type,
            team = team,
            minutes = minutes,
            extra_info = extra_info,
            player_number = player_number,
            is_additional_time = is_additional_time,
            home_team = home_team,
            away_team = away_team,
            date = date,
            player_link = player_link
        )

def load_events(driver, seuranta, logger):
    seuranta.click()
    driver\
        .find_element_by_xpath('//*[@class="controls center"]')\
        .find_element_by_xpath('//*[@data-value="all"]')\
        .click()
    src = driver.page_source
    soup = BeautifulSoup(src, 'html.parser')
    home_team = soup.find('div', {'class': 'home'}).text.strip().split('\n')[0]
    away_team = soup.find('div', {'class': 'away'}).text.strip().split('\n')[0]
    try:
        date = re.search('[0-9]{2}\.[0-9]{2}\.[0-9]{4}', soup.find('div', {'class': 'stats-wrapper'}).find('h3').text).group()
    except:
        date = '?'
    rows = soup.find_all('tr')
    res = []
    i = 1
    for row in rows:
        event_info = "event " + str(i) + "/" + str(len(rows))
        logger.info("Parsing " + event_info)
        try:
            res.append(Event.from_bs(elem=row, home_team=home_team,
                                     away_team=away_team, date=date))
        except:
            logger.exception("Failed on " + event_info)
            pass
        i += 1
    return (res, rows)

def game_row_to_dict(game_row, header):
    fields = game_row.find_elements_by_tag_name('td')
    res = {}
    i = 0
    for field in fields:
        res[header[i]] = field.text
        i += 1
    return res


def find_games(driver, logger):
    url = 'http://www.veikkausliiga.com/tilastot/2018/veikkausliiga/ottelut/'
    driver.get(url)
    games_table = driver.find_element_by_id('games')
    game_rows = games_table.find_elements_by_tag_name('tr')
    header = [d.text for d in game_rows[0].find_elements_by_tag_name('td')]
    res = []
    for game_row in game_rows:
        try:
            res.append(Game.from_dict(game_row_to_dict(game_row, header)))
        except:
            logger.exception("Failed to parse game")
    return res

def find_events(driver, logger, i, season = 2018):
    logger.info("Find events at index " + str(i))
    url = 'http://www.veikkausliiga.com/tilastot/{}/veikkausliiga/ottelut/'.format(season)
    driver.get(url)
    games_table = driver.find_element_by_id('games')
    seurannat = games_table.find_elements_by_xpath('//*[@title="Seuranta"]')
    if len(seurannat) <= i:
        logger.info("I guess we are done with events at " + str(i) + " games")
        return None
    events, rows = load_events(driver, seurannat[i], logger)
    logger.info("Parsed " + str(len(events)) + " events.")
    return events




def find_goals(events, logger):
    maalit = [e for e in events if e.event_type == "Maali"]
    ei_maalit = [e for e in events if e.event_type != "Maali"]
    logger.info("There were " + str(len(maalit)) + " goals, which will be merged to events")
    for maali in maalit:
        relevant = [e for e in ei_maalit
                    if e.team == maali.team
                    and e.minutes == maali.minutes
                    and e.player_number == maali.player_number]
        if len(relevant) > 1:
            logger.warning("Found " + str(len(relevant)) + " potential events for goal!")
            logger.warning(str(maali))
            continue
        if len(relevant) == 0:
            logger.warning("Found no relevant events for goal!")
            logger.warning(str(maali))
            continue
        relevant[0].goal = 'T'
    return ei_maalit

logger = logging.getLogger("Veikkausliiga scrape")
sh = logging.StreamHandler()
logger.setLevel(logging.INFO)
log_format = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
sh.setFormatter(log_format)
logger.addHandler(sh)


driver = webdriver.Firefox()


def write_events(season, driver, logger):
    first = True
    i = 1
    max_restarts = 3
    for i in range(0, 500):
        sleepy_time = random.random() * 1.2
        if not first:
            logger.info("Sleeping for " + str(sleepy_time))
            time.sleep(sleepy_time)
        for j in range(0, max_restarts):
            try:
                events = find_events(driver, logger, i, season)
                break
            except:
                logger.exception("Failed to find events, retry " + str(j) + "/3")
                logger.info("Retring in 5 seconds")
                time.sleep(5)
                if j > max_restarts:
                    raise
        if events is None:
            return
        if first:
            wmode = 'w'
        else:
            wmode = 'a'
        fields = events[0].__dict__.keys()
        with open("events_{}.csv".format(season), wmode) as fp:
            writer = csv.DictWriter(fp, fieldnames=fields)
            if first:
                writer.writeheader()
            for event in events:
                writer.writerow(event.__dict__)
        first = False

write_events(2018, driver, logger)

import datetime
"{}".format(datetime.datetime.now())
