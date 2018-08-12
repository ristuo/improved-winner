from selenium import webdriver
import datetime
import time
import random
import logging
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

def parse_kerroin(element):
    title = element.get_attribute('title')
    if title != 'Kerroin':
        return None
    outcome_id = element.get_attribute('data-outcome-id')
    event_id = element.get_attribute('data-event-id')
    odds = int(element.get_attribute('data-odds-original'))/100
    text = element.text.replace('\n', ' ')
    return (outcome_id, event_id, odds, text)


class Bet:
    def __init__(self, team1, team2, time):


driver = webdriver.Firefox()
veikkaus_url = 'https://www.veikkaus.fi/'
pitkaveto_url = 'https://www.veikkaus.fi/fi/pitkaveto'
driver.get(pitkaveto_url)
event_groups = driver.find_elements_by_class_name('event-group')
res = []
for event_group in event_groups:
    if event_group.get_attribute('data-offset')
    events = event_group.find_elements_by_class_name('list')
    event = events[0]
    for event in events:
        listy = event.find_elements_by_tag_name('li')
        for cell in listy:
            title = cell.find_element_by_class_name('event-title').text
            odds = [x for x in [parse_kerroin(x) for x in cell.find_elements_by_class_name('button')] if x is not None]
            desc = cell.find_element_by_class_name('event-description').text
        events[0].find_elements_by_tag_name('li')

event_groups[4].find_elements_by_class_name('date')[0].text
event_groups[0].get_attribute('data-offset')

event_group = event_groups[1]
event_group.find_elements_by_class_name('list')
event_group.get_property('data-offset')

event_group.find_elements_by_class_name('list')


x.find_elements_by_class_name("event-title")[0].text
for i in a = x.find_elements_by_class_name('button')[3]
    print(i.text)


def f():
    return None


parse_kerroin(a)
x.text.split('\n')

info.get_attribute('title')
cell.find_element_by_class_name('event-title').text