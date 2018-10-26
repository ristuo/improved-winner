from datalayer.datalayer import load_predictions, load_game_predictions, get_db_connection
from datetime import datetime
import io
import numpy as np
from flask import render_template, Response, g
import matplotlib.pyplot as plt
plt.switch_backend('SVG')
import pandas as pd
from matplotlib.backends.backend_agg import FigureCanvasAgg as FigureCanvas
from matplotlib.figure import Figure
from mpl_toolkits.mplot3d import Axes3D


from flask import Flask
app = Flask(__name__)

# game_id = 'runkosarja_2018-2019_105'

def connect_db():
    return get_db_connection('betting')

def get_preds():
    predictions_table = load_predictions()
    predictions = []
    for i in range(0, predictions_table.shape[0]):
        d = predictions_table.iloc[i].to_dict()
        d['probability'] = '{0:.3f}'.format(d['probability'])
        for k in d.keys():
            if pd.isnull(d[k]):
                d[k] = None

        if d['kelly_bet'] is not None:
            d['kelly_bet'] = '{0:.3f}'.format(d['kelly_bet'])
        if d['home_team_goals'] is not None:
            d['home_team_goals'] = int(d['home_team_goals'])
        if d['away_team_goals'] is not None:
            d['away_team_goals'] = int(d['away_team_goals'])
        d['in_past'] = datetime.now().date() > d['game_date']
        predictions.append(d)
    return predictions

@app.before_request
def before_request():
    g.db = connect_db()

@app.teardown_request
def teardown_request(exception):
    if hasattr(g, 'db'):
        g.db.close()


@app.route('/')
def hello_world():
    return 'It\'s working at least'

@app.route('/predictions')
def show_predictions():
    predictions = get_preds()
    keys = [
        'tournament',
        'game_date',
        'home_team',
        'away_team',
        'name',
        'probability',
        'odds',
        'kelly_bet',
        'open_time',
        'close_time',
        'home_team_goals',
        'away_team_goals'
    ]
    return render_template('predictions.html', predictions=predictions, keys=keys)


@app.route('/plots/jpmf-plot/<game_id>/')
def get_plot(game_id):
    predictions = get_preds()
    game = [p for p in predictions if p['game_id'] == game_id][0]
    game_df = load_game_predictions(game_id=game_id, tournament=game['tournament'], sport_name=game['sport_name'],
                                    conn=g.db)
    fig = make_plot(game_df)
    output = io.BytesIO()
    FigureCanvas(fig).print_png(output)
    return Response(output.getvalue(), mimetype='image/png')


@app.route('/game/<game_id>/')
def show_game(game_id):
    conn = g.db
    predictions=get_preds()
    game = [p for p in predictions if p['game_id'] == game_id][0]
    game_df = load_game_predictions(game_id=game_id, tournament=game['tournament'], sport_name=game['sport_name'],
                                    conn=conn)
    nrow = np.max(game_df['home_team_score']) + 1
    ncol = np.max(game_df['away_team_score']) + 1
    game_df.sort_values(['home_team_score', 'away_team_score'])
    pmat = game_df[['home_team_score', 'away_team_score', 'probability']].set_index(['home_team_score', 'away_team_score'])
    return render_template('game.html', game_id=game_id, game_df=game_df, pmat=pmat, colrange=range(0,ncol),
                           rowrange=range(0,nrow))


def make_plot(game_df):
    fig = plt.figure(figsize=(8, 3))
    ax1 = fig.add_subplot(121, projection='3d')
    ax2 = fig.add_subplot(122, projection='3d')
    ax2.view_init(60, 60)
    x = game_df['home_team_score'].values
    y = game_df['away_team_score'].values
    top = game_df['probability'].values
    width = depth = 1
    bottom = np.zeros_like(top)
    ax1.bar3d(x, y, bottom, width, depth, top, shade=True)
    ax1.set_xlabel("Home team score")
    ax1.set_ylabel("Away team score")
    fig.suptitle('Joint probability mass function')
    ax2.bar3d(x, y, bottom, width, depth, top, shade=True)
    ax2.set_xlabel("Home team score")
    ax2.set_ylabel("Away team score")
    return fig

