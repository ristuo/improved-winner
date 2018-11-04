import matplotlib.pyplot as plt
import numpy as np
plt.switch_backend('SVG')
from mpl_toolkits.mplot3d import Axes3D


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

def make_results_plot(betting_results):
    fig = plt.figure(figsize=(8, 3))
    ax = fig.add_subplot(111)
    ys = betting_results[['money_won', 'expected_value']].values
    ys = np.vstack((np.zeros((1,ys.shape[1])), ys))
    y1 = np.cumsum(ys[::, 0])
    y2 = np.cumsum(ys[::, 1])
    x = np.arange(0, ys.shape[0])
    ax.step(x,y1, '-k', label='Money won')
    ax.step(x,y2, '--r', label='EV')
    ax.yaxis.set_ticks_position('both')
    ax.xaxis.set_ticks_position('both')
    ax.tick_params(direction='in')
    ax.legend()
    ax.grid(True, linestyle='--', alpha=0.3)
    return fig

