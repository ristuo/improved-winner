select 
              game_set, game_id, event_id, games.game_date, home_team, away_team, name, odds, x.sport_name  
        from games
        left outer join 
                (select date(time) as game_date, event_id, sport_name, tournament_name, event_name, name, odds from odds) x 
        on
                x.game_date = games.game_date and
                x.sport_name = games.sport_name and
                x.tournament_name = games.tournament and
                x.event_name = concat(games.home_team, ' - ', games.away_team)
         where games.game_date < date('2018-10-22')
        order by 
                game_id
