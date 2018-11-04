from datalayer.datalayer import write_preds_to_db
import pandas as pd
import numpy as np
from model.bnb import bnb_stan
from model.util import make_datasets, predictions_to_rows
pd.set_option('display.width', 250)
pd.set_option('display.max_columns', 20)
np.set_printoptions(linewidth=300)
tournament = 'Liiga'
sport_name = 'Jääkiekko'
dataset, oos_dataset = make_datasets(
    tournament=tournament,
    sport_name=sport_name,
    expected_players_per_team=19,
    max_oos_games=20
)
samples, mean_preds = bnb_stan(dataset, oos_dataset, warmup=20000,
                               n_iter=23000)
rows = predictions_to_rows(mean_preds, oos_dataset=oos_dataset,
                           sport_name=sport_name, tournament=tournament)
write_preds_to_db(rows=rows)

