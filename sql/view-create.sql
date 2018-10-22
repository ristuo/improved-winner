create view game_odds as
select 
  game_set, 
  game_id, 
  event_id, 
  games.game_date, 
  home_team, 
  away_team, 
  name, odds, 
  x.sport_name, 
  x.tournament,
  open_time,
  close_time,
  agency,
  short_name,
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
    name, 
    close_time,
    open_time,
    agency,
    short_name,
    odds 
  from odds
  where dl_time = (select max(dl_time) from odds)
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
    select game_id, sport_name, tournament, home_team, away_team from games
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
    home_team,
    away_team,
    name;

create view odds_predictions as
  select
    game_odds.sport_name,
    game_odds.game_id,
    game_odds.tournament,
    probs.probability,
    probs.name,
    probs.newest_dl_time,
    probs.upload_time,
    game_odds.event_id,
    game_odds.open_time,
    game_odds.close_time
  from
    game_odds inner join predictions_1x2 as probs
  on
    game_odds.game_id = probs.game_id and
    game_odds.tournament = probs.tournament and
    game_odds.name = probs.name and
    game_odds.sport_name = probs.sport_name;


create view predictions_odds as
select 
        a.game_id,
        a.model_name,
        a.sport_name,
        a.tournament,
        b.game_set,
        b.game_date,
        a.home_team,
        a.away_team,
        a.name,
        a.probability,
        b.odds,
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

