import matplotlib.pyplot as plt
# This import registers the 3D projection, but is otherwise unused.
fig = plt.figure(figsize=(8, 3))
ax1 = fig.add_subplot(121, projection='3d')

x = game_df['home_team_goals'].values
y = game_df['away_team_goals'].values
top = game_df['p'].values
width = depth = 1
bottom = np.zeros_like(top)
ax1.bar3d(x, y, bottom, width, depth, top, shade=True)
ax1.set_title('Shaded')

plt.show()