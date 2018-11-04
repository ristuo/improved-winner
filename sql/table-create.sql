create table games (
  game_set varchar(100),
  game_id varchar(100),
  home_team varchar(100),
  away_team varchar(100),
  game_date date,
  season varchar(100),
  game_time time with time zone,
  tournament varchar(100),
  sport_name varchar(100),
  home_team_goals integer,
  away_team_goals integer,
  dl_time timestamp with time zone,
  primary key (game_id, tournament, game_set, season)
);

create table lineups (
  team varchar(100),
  team_type varchar(100),
  game_id varchar(100),
  league varchar(100),
  season varchar(100),
  game_set varchar(100),
  player_id varchar(100),
  player_position varchar(100),
  player_squad varchar(100),
  player_link varchar(100),
  dl_time timestamp with time zone,
  primary key (team, league, season, game_set, player_id, game_id)
);

create table odds (
  time timestamp with time zone,
  category_name varchar(100),
  odds float,
  id integer,
  event_id varchar(100),
  bet_id varchar(100),
  sport_name varchar(100),
  short_name varchar(100), 
  event_name varchar(100),
  status varchar(100),
  tournament_name varchar(100),
  name varchar(100),
  dl_time timestamp with time zone,
  close_time timestamp with time zone,
  open_time timestamp with time zone,
  agency varchar(100),
  primary key(event_id, id, dl_time)
);

create table veikkausliiga_player_stats (
  dl_time timestamp with time zone,
  exchanged_in integer,
  exchanged_out integer,
  games integer, 
  goal_passes integer,
  goals integer,
  in_start_lineup integer,
  joukkue varchar(100),
  nimi varchar(100),
  offsides integer,
  penalties integer,
  penalty_kicks integer,
  penalty_kick_goals integer,
  play_time float, 
  raw_row_number varchar(100),
  red_cards integer,
  season varchar(100), 
  shots integer,
  shots_towards_goal integer,
  sport_name varchar(100), 
  tournament_name varchar(100), 
  goal_pct float,
  yellow_cards varchar(100),
  player_id varchar(100),
  primary key(player_id, season, sport_name)
);

create table liiga_player_stats (
  dl_time timestamp with time zone,
  alivoima_goals integer,
  avg_seconds_played_per_game integer,
  games integer,
  goal_passes integer,
  goals integer,
  minuspoint integer,
  opening_pct float,
  openings integer,
  penalty_minutes integer,
  player_id varchar(100),
  player_name varchar(100),
  plusminus_difference integer,
  pluspoints integer,
  points integer,
  position varchar(100),
  raw_row_number varchar(100),
  season varchar(100),
  shot_percentage float,
  shots integer,
  sport_name varchar(100),
  team_name varchar(100),
  tournament_name varchar(100),
  winning_goals integer,
  ylivoima_goals integer,
  primary key(player_id, season, sport_name)
);

create table predictions (
  upload_time timestamp with time zone,
  game_id varchar(100),
  newest_dl_time timestamp with time zone,
  home_team_score integer,
  away_team_score integer,
  probability float,
  tournament varchar(100),
  sport_name varchar(100),
  model_name varchar(200)
);

create table bets (
  bet_time timestamp with time zone,
  game_id varchar(100),
  agency varchar(200),
  agency_bet_id varchar(100),
  bet float,
  odds float,
  sport_name varchar(100),
  tournament varchar(100),
  model_name varchar(100),
  probability float,
  bankroll float,
  outcome_id varchar(100),
  outcome_name varchar(200)
);
