--Задача 1.  В каких городах больше одного аэропорта?
--Группируем в таблице  airports по городу и смотрим где больше одного.

	select city as "Город", count(city) as "Количество аэропортов"
	from airports 
	group by city 
	having count(city)>1


--Задача 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета? (Подзапрос)
-- В подзапросе ищем самолет (aircraft_code) с максимальной дальностью (range), выбирая первую строку после обратной сортировки.
-- Далее из таблицы рейсов (flight) по уже найденому условию отбираем все аэропорты откуда вылетает этот выбранный тип самолета(aircraft_code). 
-- Подразумевается, если этот самолет вылетает из этого аэропорта, то он туда сначала прилетает, поэтому не берем аэропорт прилета. 
-- Далее, для красоты вывода,  джойним с таблицами aircrafts и airports, сортируем.
	
select  distinct concat (a3.city,'(',departure_airport,')') as "Аэропорт",
a2.model as "Самолет", a2.range as "Дальность"
from flights f
join aircrafts a2 on a2.aircraft_code =f.aircraft_code 
join airports a3 on a3.airport_code=f.departure_airport 
where a2.aircraft_code =
			(select aircraft_code 
			from aircrafts a 
			order by range desc
			limit 1)
order by "Аэропорт"
		
		

--Задача 3. Вывести 10 рейсов с максимальным временем задержки вылета. (Оператор limit)
-- Вычетаем из актуального времени вылета вылет по расписанию, без учета тех, которые null,
-- то есть не вылетели. Сортируем и ограничиваем десятью. 


select flight_no as "Номер рейса",  to_char(scheduled_departure, 'dd.mm.yyyy HH:MI:SS') as " Вылет по расписанию", 
to_char(actual_departure, 'dd.mm.yyyy HH:MI:SS') as "Реальное время вылета",
to_char(actual_departure - scheduled_departure, 'HH:MI:SS') as "Задержка рейса"
from flights 
where actual_departure is not null
order by (actual_departure - scheduled_departure) desc 
limit 10


--Задача 4. Были ли брони, по которым не были получены посадочные талоны?  (Верный тип join)
--Берам таблицу с посадочными талонами(boarding_passes) деалем left loin по ticket_no  и берем те строки (null),
--которых нет в boarding_passes (билет есть, а талона нет)

select distinct t.book_ref as "Брони без посадочных талонов"
from tickets t 
 left join boarding_passes as bp on t.ticket_no =bp.ticket_no 
 where bp.ticket_no is null


--Задача 5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
--Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта 
--на каждый день. Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного 
--аэропорта на этом или более ранних рейсах в течении дня. (Оконная функция, Подзапросы или/и cte).
--Логика: В первом СТЕ просто считаем поличество мест в разных типах самолетов.
-- Во второме СТЕ джойним вылетевшие рейсы с таблицей посадочных талонов и первым СТЕ и в оконных
 -- функциях считаем для каждого рейса разницу общего количества мест и выданных талонов = свободные места и %
 -- Так как расчет суммы в оконной функции нельзя было добавить туда где мы считали свободные места,
 -- делаем расчет отедльно в конце.

with seats_aircraft as 
	(select aircraft_code, count(seat_no)
	from seats
	group by aircraft_code),
cte2 as 
	(select distinct f.flight_id, f.departure_airport, sa.count as  c,
	count (bp.boarding_no) over (partition by f.flight_id) as c1,
	 sa.count-count (bp.boarding_no) over (partition by f.flight_id) as c2,
	(sa.count-count (bp.boarding_no) over (partition by f.flight_id))*100/sa.count as c3,
	f.actual_departure
	from flights f 
	join boarding_passes bp on bp.flight_id=f.flight_id 
	join seats_aircraft as sa on sa.aircraft_code=f.aircraft_code)
select flight_id, departure_airport as "Аэропорт", c as "Кол-во мест", cte2.c1 as "Кол-во пассажиров",
cte2.c2 as "Кол-во свободных мест",c3 as "в %",
sum(cte2.c1) over (partition by cte2.departure_airport,cte2.actual_departure::date order by cte2.actual_departure)
as "Кол-во пассажиров за день"
from cte2
order by departure_airport, actual_departure 



-- Задача 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества.(Подзапрос или окно,Оператор ROUND)
-- В подзапросе считаем количество рейсов для каждого типа самолета. В основном запросе считаем процент. 
-- Результат деления приводим к типу numeric, чтобы не терялись знаки после запятой.


select model as "Самолет", count as "Кол-во рейсов", 
round((count*100/(select count (flight_id)from flights)::numeric),1)as "в %"
from 
	(select model,count(flight_id)
	from flights
	join aircrafts using (aircraft_code)
	group by model) as t
	
-- Задача 7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета? (CTE)
-- В подзапросе с помощью оконных функций ищем минимальную и мкасимальную стоимсоть для, соответсвенно, бизнес и эконом классов
-- в каждом рейсе. В основном запросе для вывода города джойним  и вывыодим по условию, если стоимость бизнес класса 
-- была дешевле эконом.

	
with cte1 as 
	(select *, min(amount) filter (where fare_conditions ='Business' ) over (partition by flight_id) as r1,
	max(amount) filter (where fare_conditions ='Economy') over (partition by flight_id) as r2
	from ticket_flights tf)
select distinct a.city, cte1.flight_id as "Номер рейса", r1 as "Стоимость Business", r2 as "Стоимость Economy"
from cte1
join flights f on f.flight_id =cte1.flight_id 
join airports a on a.airport_code =f.arrival_airport 
where r2>r1 
		
--Задача 8. Между какими городами нет прямых рейсов? (Декартово произведение в предложении FROM,  представления except)
--9584
-- В первом представлении создаем таблицу со всеми возможными вариантами пар городов.
-- Во втором - из таблицы перелетов по кодам аэропортов находим уникальные рейсы между городами.
-- В основном запросе выводим города, между которыми нет перелетов.

create view cities as 
	select a1.city as city1, a2.city as city2
	from airports a1, airports a2 
	where a1.city != a2.city;

create view all_flights as 
	select  distinct a3.city as city1, a4.city  as city2
	from flights f 
	join airports a3 on a3.airport_code =f.departure_airport 
	join airports a4 on a4.airport_code =f. arrival_airport;

select *
from cities
except
select *
from all_flights
order by  city1, city2


--Задача 9. Вычислите расстояние между аэропортами, связанными прямыми рейсами,
--сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы.
--(Оператор RADIANS или использование sind/cosd, CASE)
-- В СТЕ джойним таблицы перелетовб аэропотов (два раза: вылет и прилет), самолеты (дальность) 
-- и считаем расстояние по формуле. В основном вопросе по условию больше меньше сравниваем дальность
-- полета самолетов и расстояние между городами.

with cte as
	(select  distinct concat (a1.city,'(',a1.airport_code,')') as c1,
	concat(a2.city,'(', a2.airport_code,')') as c2, a3.range  "Дальность полета",
	round(6371*acos(sin(radians(a1.latitude))*sin(radians(a2.latitude)) 
	+ cos(radians(a1.latitude))*cos(radians(a2.latitude))*cos(radians(a1.longitude)- radians(a2.longitude)))) as "Расстояние"
	from flights f 
	join airports a1 on a1.airport_code =f.departure_airport 
	join airports a2 on a2.airport_code =f. arrival_airport
	join aircrafts a3 on a3.aircraft_code =f.aircraft_code) 
select *,
	case 
	when "Расстояние" >= "Дальность полета" then 'Не допустимо'
	when "Расстояние" < "Дальность полета" then 'Допустимо'
	end
from cte
order by c1, c2