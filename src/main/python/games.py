import requests
from datetime import datetime
import os
import csv
import re
from bs4 import BeautifulSoup

class VeikkausliigaURLs:
    @staticmethod
    def get_url_for_year(year):
        return 'http://www.veikkausliiga.com/tilastot/{}/veikkausliiga/ottelut/'.format(year)


def download_year(year):
    url = VeikkausliigaURLs.get_url_for_year(year)
    res = requests.get(url)
    res.raise_for_status()
    res_soup = BeautifulSoup(res.content, "html.parser")
    games = res_soup.find('table', {'id': 'games'})
    header = games.find('thead')
    field_names = [x.text for x in header.find_all('td')]
    body = games.find('tbody')
    rows = body.find_all('tr')
    scrape_res = []
    for row in rows:
        d = {}
        cells = row.find_all('td')
        linky = row.find('td', {'class': 'ta-l'})
        game_id = re.findall("/([0-9]*)/$", linky.find('a')['href'])[0]
        d['game_id'] = game_id
        for i in range(0, len(cells)):
           d[field_names[i]] = cells[i].text
        scrape_res.append(d)
    return scrape_res

years = [2018, 2017, 2016]
results = [download_year(i) for i in years]
res = []
for result in results:
    res += result

date_string = datetime.now().strftime('%Y-%m-%d')
os.makedirs('data/games/' + date_string, exist_ok = True)
outpath = 'data/games/' + date_string + "/games.csv"

with open(outpath, "w") as fp:
    writer = csv.DictWriter(fp, fieldnames = res[0].keys())
    writer.writeheader()
    for row in res:
        writer.writerow(row)



