create view newest_odds_per_game as
  select 
    time, 
    category_name,
    odds,
    id,
    odds.event_id,
    sport_name,
    short_name,
    event_name,
    status,
    tournament_name,
    name,
    odds.dl_time,
    bet_id,
    close_time,
    open_time,
    agency
  from 
    odds
  inner join (
    select 
      event_id,
      max(dl_time) as dl_time
    from
      odds
    group by
      event_id
  ) x
  on
    odds.dl_time = x.dl_time and
    odds.event_id = x.event_id;
 
create view game_odds as
select 
  game_set, 
  game_id, 
  event_id, 
  games.game_date, 
  home_team, 
  away_team, 
  name, odds, 
  id as outcome_id, 
  bet_id,
  x.sport_name, 
  x.tournament,
  open_time,
  close_time,
  agency,
  short_name,
  home_team_goals,
  away_team_goals,
  x.dl_time  
from games
left join (
  select 
    date(time) as game_date, 
    event_id, 
    sport_name, 
    tournament_name as tournament, 
    dl_time, 
    event_name, 
    id, 
    bet_id,
    name, 
    close_time,
    open_time,
    agency,
    short_name,
    odds 
  from newest_odds_per_game
  ) x 
on
  x.game_date = games.game_date and
  x.sport_name = games.sport_name and
  x.tournament = games.tournament and
  x.event_name = concat(games.home_team, ' - ', games.away_team);

   

create view newest_predictions as
  select
    home_team_score, 
    away_team_score,
    predictions.game_id,
    predictions.sport_name,
    predictions.tournament,
    predictions.upload_time,
    newest_dl_time,
    teams.game_date,
    probability,
    home_team,
    away_team,
    model_name
  from 
    predictions
  inner join (
    select 
      max(upload_time) as max_upload_time, 
      tournament, 
      sport_name 
    from 
      predictions 
    group by 
      tournament, 
      sport_name
    ) max_times
  on 
    predictions.tournament = max_times.tournament and
    predictions.sport_name = max_times.sport_name
  inner join (
    select game_id, game_date, sport_name, tournament, home_team, away_team from games
  ) teams
  on 
    teams.game_id = predictions.game_id and
    teams.sport_name = predictions.sport_name and 
    teams.tournament = predictions.tournament 
  where max_upload_time = predictions.upload_time;


create view predictions_1x2 as
  select
    sum(probability) as probability,
    case when home_team_score > away_team_score then home_team
         when home_team_score < away_team_score then away_team
         when home_team_score = away_team_score then 'Tasapeli'
    end as name,
    game_id,
    model_name,
    sport_name,
    tournament,
    game_date,
    upload_time,
    newest_dl_time,
    home_team,
    away_team
  from
    newest_predictions
  group by
    game_id,
    model_name,
    sport_name,
    tournament,
    upload_time,
    newest_dl_time,
    game_date,
    home_team,
    away_team,
    name;

create view predictions_odds as
select 
        a.game_id,
        a.model_name,
        a.sport_name,
        a.tournament,
        b.game_set,
        a.game_date,
        a.home_team,
        a.away_team,
        a.name,
        a.probability,
        b.odds,
        b.bet_id,
        b.outcome_id,
        b.home_team_goals,
        b.away_team_goals,
        b.open_time,
        b.close_time,
        b.agency,
        b.short_name,
        b.dl_time as odds_dl_time,
        a.upload_time,
        a.newest_dl_time,
        b.event_id,
        a.probability > 1.0 / b.odds as should_bet,
        (((b.odds-1) * (a.probability)) - (1-a.probability)) / (b.odds-1) as kelly_bet
 from 
        predictions_1x2 as a
left join 
        game_odds as b 
on 
  a.game_id = b.game_id and 
  a.name = b.name;

create view betting_results as
SELECT
  *,  
  CASE
    WHEN observed_outcome = outcome_name THEN odds * bet -bet
    WHEN observed_outcome IS NULL THEN NULL
    ELSE -bet
  END AS money_won,
  CASE 
    WHEN observed_outcome IS NULL THEN NULL
    ELSE bet * (odds - 1) * probability
  END AS expected_value
FROM (
  SELECT
    bet_time,
    a.game_id,
    a.agency,
    a.bet,
    a.odds,
    a.probability,
    a.bankroll,
    a.sport_name,
    a.tournament,
    a.model_name,
    a.outcome_name,
    b.home_team,
    b.away_team,
    b.home_team_goals,
    b.away_team_goals,
    b.game_date,
    CASE
      WHEN home_team_goals > away_team_goals THEN home_team
      WHEN away_team_goals > home_team_goals THEN away_team
      WHEN home_team_goals IS NULL THEN NULL
      ELSE 'Tasapeli'
    END AS observed_outcome
  FROM
    bets a
  LEFT JOIN
    games b
  ON  
    a.game_id = b.game_id) x;
