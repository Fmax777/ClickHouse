CREATE TABLE user_events(
user_id UInt32,
event_type String,
points_spent UInt32,
event_time DateTime)
ENGINE = MergeTree()
ORDER BY (event_type, user_id)
TTL event_time + INTERVAL 30 days DELETE;


CREATE TABLE agg_user_events(
unique_users AggregateFunction (uniq, UInt32),
event_type String,
total_spent AggregateFunction (sum, UInt32),
event_date Date,
total_actions AggregateFunction (count))
ENGINE = AggregatingMergeTree()
ORDER BY (event_type, event_date)
TTL event_date + INTERVAL 180 days DELETE;


CREATE MATERIALIZED VIEW mv_user_agg
TO agg_user_events
AS
SELECT 
	event_type,
	toDate(event_time) AS event_date,
	sumState(points_spent) AS total_spent,
	uniqState(user_id) AS unique_users,
	countState() AS total_actions
FROM user_events
GROUP BY event_type, event_date;


INSERT INTO user_events VALUES
-- События 10 дней назад
(1, 'login', 0, now() - INTERVAL 10 DAY),
(2, 'signup', 0, now() - INTERVAL 10 DAY),
(3, 'login', 0, now() - INTERVAL 10 DAY),
-- События 7 дней назад
(1, 'login', 0, now() - INTERVAL 7 DAY),
(2, 'login', 0, now() - INTERVAL 7 DAY),
(3, 'purchase', 30, now() - INTERVAL 7 DAY),
-- События 5 дней назад
(1, 'purchase', 50, now() - INTERVAL 5 DAY),
(2, 'logout', 0, now() - INTERVAL 5 DAY),
(4, 'login', 0, now() - INTERVAL 5 DAY),
-- События 3 дня назад
(1, 'login', 0, now() - INTERVAL 3 DAY),
(3, 'purchase', 70, now() - INTERVAL 3 DAY),
(5, 'signup', 0, now() - INTERVAL 3 DAY),
-- События вчера
(2, 'purchase', 20, now() - INTERVAL 1 DAY),
(4, 'logout', 0, now() - INTERVAL 1 DAY),
(5, 'login', 0, now() - INTERVAL 1 DAY),
-- События сегодня
(1, 'purchase', 25, now()),
(2, 'login', 0, now()),
(3, 'logout', 0, now()),
(6, 'signup', 0, now()),
(6, 'purchase', 100, now());


WITH 
(SELECT 
	uniqExact(user_id) AS returned_in_7_days
FROM user_events
WHERE toDate(event_time) > today() - INTERVAL 10 DAY 
	AND toDate(event_time) <= today() - INTERVAL 3 DAY 
	AND user_id IN (SELECT DISTINCT user_id 
					FROM user_events
					WHERE toDate(event_time) = today() - INTERVAL 10 DAY )
) AS returned_in_7_days,
(SELECT uniqExact(user_id) AS total_users_day_0
FROM user_events ue 
WHERE toDate(ue.event_time) = today() - INTERVAL 10 DAY ) AS total_users_day_0
SELECT
	total_users_day_0,
	returned_in_7_days,
	returned_in_7_days / total_users_day_0 * 100 AS retention_7d_percent;


SELECT
    event_date,
    event_type,
    uniqMerge(unique_users) AS unique_users,
    countMerge(total_actions) AS total_actions,
    sumMerge(total_spent) AS total_spent
FROM agg_user_events
GROUP BY event_date, event_type;