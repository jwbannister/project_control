PGDMP         *                 w            project    10.5    11.1 �    �           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                       false            �           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                       false            �           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                       false            �           1262    16805    project    DATABASE     y   CREATE DATABASE project WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';
    DROP DATABASE project;
             john    false                        2615    16806    budgets    SCHEMA        CREATE SCHEMA budgets;
    DROP SCHEMA budgets;
             airsci    false                        2615    17300    changes    SCHEMA        CREATE SCHEMA changes;
    DROP SCHEMA changes;
             airsci    false                        2615    16807    info    SCHEMA        CREATE SCHEMA info;
    DROP SCHEMA info;
             airsci    false                        2615    16808    internal    SCHEMA        CREATE SCHEMA internal;
    DROP SCHEMA internal;
             airsci    false            	            2615    16810    projects    SCHEMA        CREATE SCHEMA projects;
    DROP SCHEMA projects;
             airsci    false            �           0    0    SCHEMA public    ACL     &   GRANT ALL ON SCHEMA public TO airsci;
                  john    false    3                       1255    17467    labor_rollup(date)    FUNCTION       CREATE FUNCTION budgets.labor_rollup(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, component_sum integer, total_cost real, personnel text, company character varying, type character, status text, labor_id integer, task_id integer, subtask_id integer, component_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
SELECT pp.project_num,
    pt.task_num,
    ps.subtask_num,
    pc.component_num,
    bl.hours*ilrs.rate AS total_cost,
    CONCAT(ips.last_name, ', ', ips.first_name) AS personnel,
    ics.abrv_name AS company,
    ics.abrv AS "type",
    ibs."desc" AS status,
    bl.labor_id,
    pt.task_id,
    ps.subtask_id,
    pc.component_id
   FROM budgets.labor bl
     JOIN projects.components pc ON pc.component_id = bl.component_id
	 JOIN projects.subtasks ps ON ps.subtask_id = pc.subtask_id	 
	 JOIN projects.tasks pt ON pt.task_id = ps.task_id	 
     JOIN projects.projects pp ON pp.project_num = pt.project_num	 
     JOIN (SELECT * FROM info.personnel_snapshot(v_date)) ips 
        ON ips.personnel_id = bl.personnel_id
     JOIN (SELECT * FROM info.personnel_levels_snapshot(v_date)) ipls 
        ON ips.personnel_id = ipls.personnel_id
     JOIN (SELECT * FROM info.level_rates_snapshot(v_date)) ilrs 
        ON ipls.level_id=ilrs.level_id
     JOIN info.billable_status ibs ON ibs.status_id = (pp.status * pt.status * ps.status)
     JOIN info.company_summary ics ON ics.company_id = ips.company_id
  ORDER BY (ROW(pp.project_num, pt.task_num, ps.subtask_num));
END;
 $$;
 1   DROP FUNCTION budgets.labor_rollup(v_date date);
       budgets       airsci    false    4                       1255    17607    subtask_budget(date)    FUNCTION       CREATE FUNCTION budgets.subtask_budget(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, labor real, travel real, nonlabor real, total_cost real, status text, task_id integer, subtask_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH
labor AS (SELECT l.subtask_id, SUM(l.total_cost) AS cost
            FROM budgets.labor_rollup(v_date) l
            GROUP BY l.subtask_id),
travel AS (SELECT tr.subtask_id, SUM(tr.total_cost) AS cost
            FROM budgets.travel_rollup(v_date) tr
            GROUP BY tr.subtask_id),
nonlabor AS (SELECT n.subtask_id, SUM(n.cost) AS cost
            FROM budgets.nonlabor_rollup n
            GROUP BY n.subtask_id)
SELECT psl.project_num, psl.task_num, psl.subtask_num,
    COALESCE(labor.cost, 0::real) AS labor,
    COALESCE(travel.cost::real, 0::real) AS travel,
    COALESCE(nonlabor.cost, 0::real) AS nonlabor,
    ROUND(COALESCE(labor.cost, 0::real)+COALESCE(travel.cost, 0::real)+COALESCE(nonlabor.cost, 0::real))::real AS total_cost,
    psl.status, psl.task_id, psl.subtask_id
FROM projects.subtask_list psl
LEFT JOIN labor USING(subtask_id)
LEFT JOIN travel USING(subtask_id)
LEFT JOIN nonlabor USING(subtask_id)
ORDER BY (psl.project_num, psl.task_num, psl.subtask_num);
END;
 $$;
 3   DROP FUNCTION budgets.subtask_budget(v_date date);
       budgets       airsci    false    4                       1255    17503    subtask_budget_updated(date)    FUNCTION     �  CREATE FUNCTION budgets.subtask_budget_updated(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, labor real, nonlabor real, travel real, total real, subtask_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH c AS (SELECT * FROM changes.subtask_changes(v_date))
SELECT bsp.project_num, bsp.task_num, bsp.subtask_num,
    bsp.labor::real+c.labor_change AS labor, 
    bsp.nonlabor::real+c.nonlabor_change AS nonlabor, 
    bsp.travel::real+c.travel_change AS travel, 
    bsp.total_cost::real+c.total_change AS total,
	bsp.subtask_id
FROM budgets.subtask_budget('2019-01-01') bsp
JOIN c on c.subtask_id=bsp.subtask_id
ORDER BY (bsp.project_num, bsp.task_num, bsp.subtask_num);
END;
 $$;
 ;   DROP FUNCTION budgets.subtask_budget_updated(v_date date);
       budgets       airsci    false    4                       1255    17612    subtask_utilization(date)    FUNCTION     t	  CREATE FUNCTION budgets.subtask_utilization(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, prm_dollars real, sbe_dollars real, obe_dollars real, prm_percent text, sbe_percent text, obe_percent text, subtask_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH 
ur AS (
        SELECT sq.subtask_id,
        sq.abrv,
        round(sum(sq.cost)) AS cost
        FROM ( SELECT tr.subtask_id,
                tr."type" AS abrv,
                round(sum(tr.total_cost)) AS cost
                FROM budgets.travel_rollup(v_date) tr
                GROUP BY tr.subtask_id, tr."type"
            UNION
                SELECT lr.subtask_id,
                lr.type AS abrv,
                round(sum(lr.total_cost)) AS cost
                FROM budgets.labor_rollup(v_date) lr
                GROUP BY lr.subtask_id, lr.type
            UNION
                SELECT nlr.subtask_id,
                nlr.abrv,
                round(sum(nlr.cost)::double precision) AS cost
                FROM budgets.nonlabor_rollup nlr
                GROUP BY nlr.subtask_id, nlr.abrv) sq
        GROUP BY sq.subtask_id, sq.abrv
    ), prm AS (
        SELECT ur.subtask_id,
        ur.cost
        FROM ur
        WHERE ur.abrv = 'PRM'::bpchar
    ), sbe AS (
        SELECT ur.subtask_id,
        ur.cost
        FROM ur
        WHERE ur.abrv = 'SBE'::bpchar
    ), obe AS (
        SELECT ur.subtask_id,
        ur.cost
        FROM ur
        WHERE ur.abrv = 'OBE'::bpchar
    )
SELECT psl.project_num,
psl.task_num,
psl.subtask_num,
COALESCE(sum(prm.cost)::real, 0::real) AS prm_dollars,
COALESCE(sum(sbe.cost::real), 0::real) AS sbe_dollars,
COALESCE(sum(obe.cost)::real, 0::real) AS obe_dollars,
to_char(COALESCE(sum(prm.cost)::real, 0::real) / sum(bsb.total_cost), '9.00'::text) AS prm_percent,
to_char(COALESCE(sum(sbe.cost)::real, 0::real) / sum(bsb.total_cost), '9.00'::text) AS sbe_percent,
to_char(COALESCE(sum(obe.cost)::real, 0::real) / sum(bsb.total_cost), '9.00'::text) AS obe_percent,
psl.subtask_id
FROM projects.subtask_list psl
    LEFT JOIN prm USING (subtask_id)
    LEFT JOIN sbe USING (subtask_id)
    LEFT JOIN obe USING (subtask_id)
    LEFT JOIN (SELECT * FROM budgets.subtask_budget('2019-01-01')) bsb USING (subtask_id)
GROUP BY psl.project_num, psl.task_num, psl.subtask_num, psl.subtask_id
ORDER BY psl.project_num, psl.task_num, psl.subtask_num;
END;
 $$;
 8   DROP FUNCTION budgets.subtask_utilization(v_date date);
       budgets       airsci    false    4                       1255    17507 !   subtask_utilization_updated(date)    FUNCTION     k  CREATE FUNCTION budgets.subtask_utilization_updated(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, prm_dollars real, sbe_dollars real, obe_dollars real, prm_percent text, sbe_percent text, obe_percent text)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH c AS (SELECT * FROM changes.subtask_utilization_changes(v_date))
SELECT bsu.project_num, bsu.task_num, bsu.subtask_num,
    bsu.prm_dollars::real+c.prm_change AS prm_dollars, 
    bsu.sbe_dollars::real+c.sbe_change AS sbe_dollars, 
    bsu.obe_dollars::real+c.obe_change AS obe_dollars, 
	to_char((bsu.prm_dollars::real+c.prm_change) / bsbu.total, '9.00'::text) AS prm_percent,
	to_char((bsu.sbe_dollars::real+c.sbe_change) / bsbu.total, '9.00'::text) AS sbe_percent,
	to_char((bsu.obe_dollars::real+c.obe_change) / bsbu.total, '9.00'::text) AS obe_percent															 
FROM budgets.subtask_utilization('2019-01-01') bsu
JOIN c on c.subtask_id=bsu.subtask_id
JOIN (SELECT * FROM budgets.subtask_budget_updated(v_date)) bsbu on bsu.subtask_id=bsbu.subtask_id
ORDER BY (bsu.project_num, bsu.task_num, bsu.subtask_num);
END;
 $$;
 @   DROP FUNCTION budgets.subtask_utilization_updated(v_date date);
       budgets       airsci    false    4                       1255    17614    travel_rollup(date)    FUNCTION     �  CREATE FUNCTION budgets.travel_rollup(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, description text, num_trips integer, num_staff integer, days integer, "from" text, "to" text, air_travel text, company character varying, type character, total_cost real, subtask_status text, task_id integer, subtask_id integer, trip_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH travel_id_rollup AS (
         WITH lodging AS (
                 SELECT trs.rate
                   FROM (SELECT * FROM info.travel_rates_snapshot(v_date)) trs
                  WHERE trs.type_id = 2
                ), car_rental AS (
                 SELECT trs.rate
                   FROM (SELECT * FROM info.travel_rates_snapshot(v_date)) trs
                  WHERE trs.type_id = 3
                ), meals AS (
                 SELECT trs.rate
                   FROM (SELECT * FROM info.travel_rates_snapshot(v_date)) trs
                  WHERE trs.type_id = 4
                ), mileage AS (
                 SELECT trs.rate
                   FROM (SELECT * FROM info.travel_rates_snapshot(v_date)) trs
                  WHERE trs.type_id = 5
                )
         SELECT bt.trip_id,
            bt."desc" AS description,
            bt.num_trips,
            bt.num_staff,
            bt.days,
            bt."from",
            bt."to",
            ics.abrv_name,
            ics.abrv,
            bt.subtask_id,
            itrs.desc AS air_travel,
            itrs.rate * bt.num_staff::real * bt.num_trips::real AS air_cost,
                CASE
                    WHEN bt.lodging THEN (bt.num_trips * bt.num_staff * (bt.days - 1))::real * lodging.rate
                    ELSE 0::real
                END AS lodging_cost,
                CASE
                    WHEN bt.num_rental_cars > 0 THEN (bt.num_trips * bt.days * bt.num_rental_cars)::real * car_rental.rate
                    ELSE 0::real
                END AS car_rental_cost,
                CASE
                    WHEN bt.meals THEN (bt.num_trips * bt.days * bt.num_staff)::real * meals.rate
                    ELSE 0::real
                END AS meals_cost,
                CASE
                    WHEN bt.mileage > 0::real THEN bt.num_trips::real * bt.mileage * mileage.rate
                    ELSE 0::real
                END AS mileage_cost
           FROM budgets.travel bt
             JOIN (SELECT * FROM info.travel_rates_snapshot(v_date)) itrs ON bt.air_travel_id = itrs.travel_id
             JOIN info.company_summary ics ON bt.company_id = ics.company_id
             JOIN lodging ON true
             JOIN car_rental ON true
             JOIN meals ON true
             JOIN mileage ON true
        )
 SELECT pp.project_num,
    pt.task_num,
    ps.subtask_num,
    tir.description,
    tir.num_trips,
    tir.num_staff,
    tir.days,
    tir."from",
    tir."to",
	tir.air_travel, 
    tir.abrv_name AS company,
    tir.abrv AS "type",
    travel_cost_totals.total_cost,
    ibs."desc" AS subtask_status,
    pt.task_id,
    ps.subtask_id,
    tir.trip_id
   FROM travel_id_rollup tir
     JOIN projects.subtasks ps ON ps.subtask_id = tir.subtask_id
     JOIN projects.tasks pt ON pt.task_id = ps.task_id
     JOIN projects.projects pp ON pp.project_num = pt.project_num
     JOIN info.billable_status ibs ON ibs.status_id = ps.status
     JOIN ( SELECT travel_id_rollup.trip_id,
            travel_id_rollup.air_cost + travel_id_rollup.lodging_cost + travel_id_rollup.car_rental_cost + travel_id_rollup.meals_cost + travel_id_rollup.mileage_cost AS total_cost
           FROM travel_id_rollup) travel_cost_totals ON tir.trip_id = travel_cost_totals.trip_id
	ORDER BY (pp.project_num, pt.task_num, ps.subtask_num);
END;
 $$;
 2   DROP FUNCTION budgets.travel_rollup(v_date date);
       budgets       airsci    false    4                       1255    17404    subtask_changes(date)    FUNCTION     �  CREATE FUNCTION changes.subtask_changes(v_date date) RETURNS TABLE(subtask_id integer, labor_change real, nonlabor_change real, travel_change real, total_change real)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY WITH
lc AS (SELECT clr.subtask_id, SUM(clr.value) AS labor_change
        FROM changes.labor_rollup clr
        WHERE clr.date < v_date::date
        GROUP BY clr.subtask_id),
nc AS (SELECT cnr.subtask_id, SUM(cnr.value) AS nonlabor_change
        FROM changes.nonlabor_rollup cnr
        WHERE cnr.date < v_date::date
        GROUP BY cnr.subtask_id),
tc AS (SELECT ctr.subtask_id, SUM(ctr.value) AS travel_change
        FROM changes.travel_rollup ctr
        WHERE ctr.date < v_date::date
        GROUP BY ctr.subtask_id)
SELECT ps.subtask_id,
    COALESCE(lc.labor_change::real, 0::real) AS labor_change,
    COALESCE(nc.nonlabor_change::real, 0::real) AS nonlabor_change,
    COALESCE(tc.travel_change::real, 0::real) AS travel_change,
	COALESCE(lc.labor_change::real, 0::real)+COALESCE(nc.nonlabor_change::real, 0::real)+COALESCE(tc.travel_change::real, 0::real) AS total_change
FROM projects.subtasks ps
LEFT JOIN lc USING(subtask_id)
LEFT JOIN nc USING(subtask_id)
LEFT JOIN tc USING(subtask_id);
END;
 $$;
 4   DROP FUNCTION changes.subtask_changes(v_date date);
       changes       airsci    false    12                       1255    17632 !   subtask_utilization_changes(date)    FUNCTION     �  CREATE FUNCTION changes.subtask_utilization_changes(v_date date) RETURNS TABLE(subtask_id integer, prm_change real, sbe_change real, obe_change real, total_change real)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY 
WITH
rollup AS (SELECT lr.subtask_id, lr."desc", lr.date, lr.type AS abrv, lr.value
            FROM changes.labor_rollup lr
            UNION
            SELECT tr.subtask_id, tr."desc", tr.date, tr.abrv, tr.value
            FROM changes.travel_rollup tr
            UNION
            SELECT nl.subtask_id, nl."desc", nl.date, nl.abrv, nl.value
            FROM changes.nonlabor_rollup nl),
prm AS (SELECT r1.subtask_id, SUM(r1.value) AS change
        FROM rollup r1
        WHERE r1.date < v_date AND r1.abrv='PRM'
        GROUP BY r1.subtask_id),
sbe AS (SELECT r2.subtask_id, SUM(r2.value) AS change
       FROM rollup r2
        WHERE r2.date < v_date AND r2.abrv='SBE'
        GROUP BY r2.subtask_id),
obe AS (SELECT r3.subtask_id, SUM(r3.value) AS change
        FROM rollup r3
        WHERE r3.date < v_date AND r3.abrv='OBE'
        GROUP BY r3.subtask_id)
SELECT ps.subtask_id,
    COALESCE(prm.change::real, 0::real) AS prm_change,
    COALESCE(sbe.change::real, 0::real) AS sbe_change,
    COALESCE(obe.change::real, 0::real) AS obe_change,
	COALESCE(prm.change::real, 0::real)+COALESCE(sbe.change::real, 0::real)+COALESCE(obe.change::real, 0::real) AS total_change
FROM projects.subtasks ps
LEFT JOIN prm USING(subtask_id)
LEFT JOIN sbe USING(subtask_id)
LEFT JOIN obe USING(subtask_id);
END;
 $$;
 @   DROP FUNCTION changes.subtask_utilization_changes(v_date date);
       changes       airsci    false    12            
           1255    17452    level_rates_snapshot(date)    FUNCTION     �  CREATE FUNCTION info.level_rates_snapshot(v_date date) RETURNS TABLE(level_id integer, rate real)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
SELECT ibr.level_id, ibr.rate 
FROM info.billing_rates ibr
RIGHT JOIN (
	SELECT ibr2.level_id, MAX(ibr2.start_date) AS rate_start
	FROM info.billing_rates ibr2
	WHERE ibr2.start_date <= v_date 
	GROUP BY ibr2.level_id) mxdt
ON mxdt.level_id=ibr.level_id AND mxdt.rate_start=ibr.start_date
;
END;
 $$;
 6   DROP FUNCTION info.level_rates_snapshot(v_date date);
       info       airsci    false    6            	           1255    17451    personnel_levels_snapshot(date)    FUNCTION     H  CREATE FUNCTION info.personnel_levels_snapshot(v_date date) RETURNS TABLE(personnel_id integer, level_id integer, level text)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
SELECT ipl.personnel_id, ipl.level_id, itl.desc as "level" 
FROM info.personnel_levels ipl
RIGHT JOIN (
	SELECT ipl2.personnel_id, MAX(ipl2.start_date) AS level_start
	FROM info.personnel_levels ipl2
	WHERE ipl2.start_date <= v_date 
	GROUP BY ipl2.personnel_id) mxdt
ON mxdt.personnel_id=ipl.personnel_id AND mxdt.level_start=ipl.start_date
JOIN info.level_types itl ON itl.level_id=ipl.level_id
;
END;
 $$;
 ;   DROP FUNCTION info.personnel_levels_snapshot(v_date date);
       info       airsci    false    6                       1255    17466    personnel_snapshot(date)    FUNCTION     /  CREATE FUNCTION info.personnel_snapshot(v_date date) RETURNS TABLE(personnel_id integer, first_name text, last_name text, level text, company character varying, type character, rate real, company_id integer, level_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
SELECT ip.personnel_id,
    ip.first_name,
    ip.last_name,
    pls."level",
    ic.abrv_name AS company,
    ict.abrv AS "type",
    lrs.rate,
	ic.company_id,
	pls.level_id
   FROM info.personnel_info ip
     JOIN (SELECT * FROM info.personnel_levels_snapshot(v_date)) pls ON ip.personnel_id = pls.personnel_id
     JOIN info.companies ic ON ip.company_id = ic.company_id
     JOIN info.company_type ict ON ic.type_id = ict.type_id
     JOIN (SELECT * FROM info.level_rates_snapshot(v_date)) lrs ON pls.level_id = lrs.level_id;
END;
 $$;
 4   DROP FUNCTION info.personnel_snapshot(v_date date);
       info       airsci    false    6                       1255    17592    travel_rates_snapshot(date)    FUNCTION     �  CREATE FUNCTION info.travel_rates_snapshot(v_date date) RETURNS TABLE(travel_id integer, type_id integer, "desc" text, rate real)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
SELECT it.travel_id, itt.type_id,
    CONCAT(itt.desc, ' ', it.origin, ' ', it.destination) AS desc,
    itr.rate
    FROM info.travel it
    JOIN info.travel_type itt USING (type_id)
    JOIN info.travel_rates itr USING (travel_id)
    RIGHT JOIN (
        SELECT itr2.travel_id, MAX(itr2.start_date) as rate_start
        FROM info.travel_rates itr2
        WHERE itr2.start_date <= v_date
        GROUP BY itr2.travel_id) itr2
        ON itr2.travel_id=itr.travel_id AND itr2.rate_start=itr.start_date;
END;
 $$;
 7   DROP FUNCTION info.travel_rates_snapshot(v_date date);
       info       airsci    false    6            �            1259    16811    labor    TABLE     �   CREATE TABLE budgets.labor (
    labor_id integer NOT NULL,
    personnel_id integer NOT NULL,
    hours real NOT NULL,
    component_id integer NOT NULL,
    "desc" text
);
    DROP TABLE budgets.labor;
       budgets         airsci    false    4            �            1259    16814    labor_budget_labor_budge_id_seq    SEQUENCE     �   CREATE SEQUENCE budgets.labor_budget_labor_budge_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 7   DROP SEQUENCE budgets.labor_budget_labor_budge_id_seq;
       budgets       airsci    false    4    201            �           0    0    labor_budget_labor_budge_id_seq    SEQUENCE OWNED BY     X   ALTER SEQUENCE budgets.labor_budget_labor_budge_id_seq OWNED BY budgets.labor.labor_id;
            budgets       airsci    false    202            �            1259    16868    nonlabor    TABLE     �   CREATE TABLE budgets.nonlabor (
    nonlabor_id integer NOT NULL,
    subtask_id integer NOT NULL,
    cost real NOT NULL,
    "desc" text NOT NULL,
    company_id integer NOT NULL
);
    DROP TABLE budgets.nonlabor;
       budgets         airsci    false    4            �            1259    16874 (   non_labor_budget_non_labor_budget_id_seq    SEQUENCE     �   CREATE SEQUENCE budgets.non_labor_budget_non_labor_budget_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 @   DROP SEQUENCE budgets.non_labor_budget_non_labor_budget_id_seq;
       budgets       airsci    false    4    209            �           0    0 (   non_labor_budget_non_labor_budget_id_seq    SEQUENCE OWNED BY     g   ALTER SEQUENCE budgets.non_labor_budget_non_labor_budget_id_seq OWNED BY budgets.nonlabor.nonlabor_id;
            budgets       airsci    false    210            �            1259    16933    billable_status    TABLE     W   CREATE TABLE info.billable_status (
    status_id integer NOT NULL,
    "desc" text
);
 !   DROP TABLE info.billable_status;
       info         airsci    false    6            �            1259    16829 	   companies    TABLE     �   CREATE TABLE info.companies (
    company_id integer NOT NULL,
    full_name text,
    abrv_name character varying(8) NOT NULL,
    type_id integer NOT NULL
);
    DROP TABLE info.companies;
       info         airsci    false    6            �            1259    16835    company_type    TABLE     {   CREATE TABLE info.company_type (
    type_id integer NOT NULL,
    abrv character(3) NOT NULL,
    "desc" text NOT NULL
);
    DROP TABLE info.company_type;
       info         airsci    false    6            �            1259    16876    company_summary    VIEW     �   CREATE VIEW info.company_summary AS
 SELECT ic.company_id,
    ic.abrv_name,
    ict.type_id,
    ict.abrv
   FROM (info.companies ic
     JOIN info.company_type ict ON ((ic.type_id = ict.type_id)));
     DROP VIEW info.company_summary;
       info       airsci    false    206    206    205    205    205    6            �            1259    16991    projects    TABLE     �   CREATE TABLE projects.projects (
    project_num integer NOT NULL,
    "desc" text NOT NULL,
    status integer NOT NULL,
    start_date date NOT NULL
);
    DROP TABLE projects.projects;
       projects         airsci    false    9            �            1259    16907    subtasks    TABLE     �   CREATE TABLE projects.subtasks (
    subtask_id integer NOT NULL,
    task_id integer NOT NULL,
    status integer NOT NULL,
    "desc" text NOT NULL,
    subtask_num integer NOT NULL,
    start_date date NOT NULL
);
    DROP TABLE projects.subtasks;
       projects         airsci    false    9            �            1259    16913    tasks    TABLE     �   CREATE TABLE projects.tasks (
    task_id integer NOT NULL,
    "desc" text NOT NULL,
    status integer NOT NULL,
    project_num integer NOT NULL,
    task_num integer NOT NULL
);
    DROP TABLE projects.tasks;
       projects         airsci    false    9            �            1259    17252    nonlabor_rollup    VIEW     �  CREATE VIEW budgets.nonlabor_rollup WITH (security_barrier='false') AS
 SELECT pp.project_num,
    pt.task_num,
    ps.subtask_num,
    bnl."desc",
    bnl.cost,
    ibs."desc" AS status,
    pt.task_id,
    ps.subtask_id,
    ics.abrv,
    bnl.nonlabor_id,
    ics.abrv_name
   FROM (((((budgets.nonlabor bnl
     JOIN projects.subtasks ps ON ((ps.subtask_id = bnl.subtask_id)))
     JOIN projects.tasks pt ON ((pt.task_id = ps.task_id)))
     JOIN projects.projects pp ON ((pp.project_num = pt.project_num)))
     JOIN info.billable_status ibs ON ((ibs.status_id = ((pp.status * pt.status) * ps.status))))
     JOIN info.company_summary ics ON ((ics.company_id = bnl.company_id)))
  ORDER BY ROW(pp.project_num, pt.task_num, ps.subtask_num);
 #   DROP VIEW budgets.nonlabor_rollup;
       budgets       airsci    false    213    213    213    213    211    214    214    211    211    209    230    230    217    217    214    214    209    209    209    209    4            �            1259    16884    travel    TABLE     Z  CREATE TABLE budgets.travel (
    trip_id integer NOT NULL,
    air_travel_id integer,
    days integer,
    num_staff integer,
    num_trips integer,
    subtask_id integer,
    company_id integer NOT NULL,
    "desc" text,
    lodging boolean,
    meals boolean,
    mileage real,
    num_rental_cars integer,
    "from" text,
    "to" text
);
    DROP TABLE budgets.travel;
       budgets         airsci    false    4            �            1259    16929 "   travel_budget_travel_budget_id_seq    SEQUENCE     �   CREATE SEQUENCE budgets.travel_budget_travel_budget_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 :   DROP SEQUENCE budgets.travel_budget_travel_budget_id_seq;
       budgets       airsci    false    4    212            �           0    0 "   travel_budget_travel_budget_id_seq    SEQUENCE OWNED BY     [   ALTER SEQUENCE budgets.travel_budget_travel_budget_id_seq OWNED BY budgets.travel.trip_id;
            budgets       airsci    false    215            �            1259    17405    deactivations    TABLE     �   CREATE TABLE changes.deactivations (
    deactivation_id integer NOT NULL,
    subtask_id integer NOT NULL,
    date date NOT NULL
);
 "   DROP TABLE changes.deactivations;
       changes         airsci    false    12            �            1259    17317    labor    TABLE     �   CREATE TABLE changes.labor (
    labor_change_id integer NOT NULL,
    labor_id integer NOT NULL,
    value double precision NOT NULL,
    package_id integer NOT NULL
);
    DROP TABLE changes.labor;
       changes         airsci    false    12            �            1259    17309    packages    TABLE     �   CREATE TABLE changes.packages (
    package_id integer NOT NULL,
    type_id integer NOT NULL,
    date date NOT NULL,
    "desc" text
);
    DROP TABLE changes.packages;
       changes         airsci    false    12            �            1259    17301    types    TABLE     W   CREATE TABLE changes.types (
    type_id integer NOT NULL,
    "desc" text NOT NULL
);
    DROP TABLE changes.types;
       changes         airsci    false    12            �            1259    17485    labor_rollup    VIEW     �  CREATE VIEW changes.labor_rollup AS
 SELECT blr.project_num,
    blr.task_num,
    blr.subtask_num,
    ct."desc",
    cp.date,
    blr.company,
    blr.type,
    cl.value,
    blr.task_id,
    blr.subtask_id,
    blr.labor_id,
    cl.package_id
   FROM (((changes.labor cl
     JOIN ( SELECT labor_rollup.project_num,
            labor_rollup.task_num,
            labor_rollup.subtask_num,
            labor_rollup.component_sum,
            labor_rollup.total_cost,
            labor_rollup.personnel,
            labor_rollup.company,
            labor_rollup.type,
            labor_rollup.status,
            labor_rollup.labor_id,
            labor_rollup.task_id,
            labor_rollup.subtask_id,
            labor_rollup.component_id
           FROM budgets.labor_rollup('2019-01-01'::date) labor_rollup(project_num, task_num, subtask_num, component_sum, total_cost, personnel, company, type, status, labor_id, task_id, subtask_id, component_id)) blr ON ((blr.labor_id = cl.labor_id)))
     JOIN changes.packages cp ON ((cp.package_id = cl.package_id)))
     JOIN changes.types ct ON ((ct.type_id = cp.type_id)))
  ORDER BY ROW(blr.project_num, blr.task_num, blr.subtask_num);
     DROP VIEW changes.labor_rollup;
       changes       airsci    false    236    236    269    234    234    235    235    235    236    12            �            1259    17322    nonlabor    TABLE     �   CREATE TABLE changes.nonlabor (
    nonlabor_change_id integer NOT NULL,
    nonlabor_id integer NOT NULL,
    value double precision NOT NULL,
    package_id integer NOT NULL
);
    DROP TABLE changes.nonlabor;
       changes         airsci    false    12            �            1259    17390    nonlabor_rollup    VIEW     0  CREATE VIEW changes.nonlabor_rollup AS
 SELECT bnr.project_num,
    bnr.task_num,
    bnr.subtask_num,
    ct."desc",
    cp.date,
    bnr.abrv_name,
    bnr.abrv,
    cnl.value,
    bnr.task_id,
    bnr.subtask_id,
    bnr.nonlabor_id,
    cnl.package_id
   FROM (((changes.nonlabor cnl
     JOIN budgets.nonlabor_rollup bnr ON ((bnr.nonlabor_id = cnl.nonlabor_id)))
     JOIN changes.packages cp ON ((cp.package_id = cnl.package_id)))
     JOIN changes.types ct ON ((ct.type_id = cp.type_id)))
  ORDER BY ROW(bnr.project_num, bnr.task_num, bnr.subtask_num);
 #   DROP VIEW changes.nonlabor_rollup;
       changes       airsci    false    233    237    237    237    235    235    235    234    234    233    233    233    233    233    233    233    12            �            1259    17327    travel    TABLE     �   CREATE TABLE changes.travel (
    travel_change_id integer NOT NULL,
    trip_id integer NOT NULL,
    value double precision NOT NULL,
    package_id integer NOT NULL
);
    DROP TABLE changes.travel;
       changes         airsci    false    12            �            1259    17625    package_summary    VIEW     �  CREATE VIEW changes.package_summary AS
 WITH labor AS (
         SELECT l.package_id,
            sum(l.value) AS total
           FROM (changes.labor l
             JOIN changes.packages USING (package_id))
          GROUP BY l.package_id
        ), travel AS (
         SELECT tr.package_id,
            sum(tr.value) AS total
           FROM (changes.travel tr
             JOIN changes.packages USING (package_id))
          GROUP BY tr.package_id
        ), nonlabor AS (
         SELECT nl.package_id,
            sum(nl.value) AS total
           FROM (changes.nonlabor nl
             JOIN changes.packages USING (package_id))
          GROUP BY nl.package_id
        )
 SELECT cp.package_id,
    ct."desc",
    cp.date,
    ((labor.total + travel.total) + nonlabor.total) AS total
   FROM ((((changes.packages cp
     JOIN changes.types ct USING (type_id))
     JOIN labor USING (package_id))
     JOIN travel USING (package_id))
     JOIN nonlabor USING (package_id));
 #   DROP VIEW changes.package_summary;
       changes       airsci    false    234    238    238    237    237    236    235    234    236    235    235    12            �            1259    17615    travel_rollup    VIEW     �  CREATE VIEW changes.travel_rollup AS
 SELECT btr.project_num,
    btr.task_num,
    btr.subtask_num,
    ct."desc",
    cp.date,
    btr.company AS abrv_name,
    btr.type AS abrv,
    ctr.value,
    btr.task_id,
    btr.subtask_id,
    btr.trip_id,
    ctr.package_id
   FROM (((changes.travel ctr
     JOIN budgets.travel_rollup('2019-01-01'::date) btr(project_num, task_num, subtask_num, description, num_trips, num_staff, days, "from", "to", air_travel, company, type, total_cost, subtask_status, task_id, subtask_id, trip_id) ON ((btr.trip_id = ctr.trip_id)))
     JOIN changes.packages cp ON ((cp.package_id = ctr.package_id)))
     JOIN changes.types ct ON ((ct.type_id = cp.type_id)))
  ORDER BY ROW(btr.project_num, btr.task_num, btr.subtask_num);
 !   DROP VIEW changes.travel_rollup;
       changes       airsci    false    234    234    235    235    235    238    238    238    272    12            �            1259    16819    personnel_info    TABLE     �   CREATE TABLE info.personnel_info (
    personnel_id integer NOT NULL,
    company_id integer NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    cell_phone text,
    work_phone text,
    email text
);
     DROP TABLE info.personnel_info;
       info         airsci    false    6            �            1259    16931    Personnel_personnel_id_seq    SEQUENCE     �   CREATE SEQUENCE info."Personnel_personnel_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 1   DROP SEQUENCE info."Personnel_personnel_id_seq";
       info       airsci    false    204    6            �           0    0    Personnel_personnel_id_seq    SEQUENCE OWNED BY     \   ALTER SEQUENCE info."Personnel_personnel_id_seq" OWNED BY info.personnel_info.personnel_id;
            info       airsci    false    216            �            1259    16816    billing_rates    TABLE     �   CREATE TABLE info.billing_rates (
    level_id integer NOT NULL,
    rate real NOT NULL,
    rate_id integer NOT NULL,
    start_date date NOT NULL
);
    DROP TABLE info.billing_rates;
       info         airsci    false    6            �            1259    16939 !   billing_rates_billing_rate_id_seq    SEQUENCE     �   CREATE SEQUENCE info.billing_rates_billing_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 6   DROP SEQUENCE info.billing_rates_billing_rate_id_seq;
       info       airsci    false    6    203            �           0    0 !   billing_rates_billing_rate_id_seq    SEQUENCE OWNED BY     \   ALTER SEQUENCE info.billing_rates_billing_rate_id_seq OWNED BY info.billing_rates.level_id;
            info       airsci    false    218            �            1259    16841    level_types    TABLE     s   CREATE TABLE info.level_types (
    level_id integer NOT NULL,
    company_id integer NOT NULL,
    "desc" text
);
    DROP TABLE info.level_types;
       info         airsci    false    6            �            1259    17428    personnel_levels    TABLE     �   CREATE TABLE info.personnel_levels (
    personnel_id integer NOT NULL,
    level_id integer NOT NULL,
    start_date date NOT NULL,
    personnel_level_id integer NOT NULL
);
 "   DROP TABLE info.personnel_levels;
       info         airsci    false    6            �            1259    17508    travel    TABLE     �   CREATE TABLE info.travel (
    type_id integer NOT NULL,
    origin text,
    destination text,
    travel_id integer NOT NULL
);
    DROP TABLE info.travel;
       info         airsci    false    6            �            1259    17558    travel_rates    TABLE     �   CREATE TABLE info.travel_rates (
    rate real NOT NULL,
    units text NOT NULL,
    start_date date NOT NULL,
    travel_rate_id integer NOT NULL,
    travel_id integer
);
    DROP TABLE info.travel_rates;
       info         airsci    false    6            �            1259    17567     travel_rates_travel_rate_id_seq1    SEQUENCE     �   CREATE SEQUENCE info.travel_rates_travel_rate_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 5   DROP SEQUENCE info.travel_rates_travel_rate_id_seq1;
       info       airsci    false    248    6            �           0    0     travel_rates_travel_rate_id_seq1    SEQUENCE OWNED BY     `   ALTER SEQUENCE info.travel_rates_travel_rate_id_seq1 OWNED BY info.travel_rates.travel_rate_id;
            info       airsci    false    249            �            1259    17544    travel_travel_id_seq    SEQUENCE     �   CREATE SEQUENCE info.travel_travel_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE info.travel_travel_id_seq;
       info       airsci    false    244    6            �           0    0    travel_travel_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE info.travel_travel_id_seq OWNED BY info.travel.travel_id;
            info       airsci    false    247            �            1259    17516    travel_type    TABLE     Z   CREATE TABLE info.travel_type (
    "desc" text NOT NULL,
    type_id integer NOT NULL
);
    DROP TABLE info.travel_type;
       info         airsci    false    6            �            1259    17533    travel_type_type_id_seq    SEQUENCE     �   CREATE SEQUENCE info.travel_type_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ,   DROP SEQUENCE info.travel_type_type_id_seq;
       info       airsci    false    6    245            �           0    0    travel_type_type_id_seq    SEQUENCE OWNED BY     O   ALTER SEQUENCE info.travel_type_type_id_seq OWNED BY info.travel_type.type_id;
            info       airsci    false    246            �            1259    16943 	   estimated    TABLE     ^   CREATE TABLE internal.estimated (
    estimated_id bigint NOT NULL,
    subtask_id integer
);
    DROP TABLE internal.estimated;
       internal         airsci    false    11            �            1259    16946    estimated_estimated_id_seq    SEQUENCE     �   CREATE SEQUENCE internal.estimated_estimated_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 3   DROP SEQUENCE internal.estimated_estimated_id_seq;
       internal       airsci    false    219    11            �           0    0    estimated_estimated_id_seq    SEQUENCE OWNED BY     ]   ALTER SEQUENCE internal.estimated_estimated_id_seq OWNED BY internal.estimated.estimated_id;
            internal       airsci    false    220            �            1259    16948    invoice    TABLE     �   CREATE TABLE internal.invoice (
    invoice_id bigint NOT NULL,
    subtask_id integer,
    class text,
    company text,
    personnel_id integer
);
    DROP TABLE internal.invoice;
       internal         airsci    false    11            �            1259    16954    invoice_invoice_id_seq    SEQUENCE     �   CREATE SEQUENCE internal.invoice_invoice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 /   DROP SEQUENCE internal.invoice_invoice_id_seq;
       internal       airsci    false    11    221            �           0    0    invoice_invoice_id_seq    SEQUENCE OWNED BY     U   ALTER SEQUENCE internal.invoice_invoice_id_seq OWNED BY internal.invoice.invoice_id;
            internal       airsci    false    222            �            1259    16956 
   labor_burn    TABLE     �   CREATE TABLE internal.labor_burn (
    labor_burn_id bigint NOT NULL,
    subtask_breakdown_id integer,
    personnel_id integer,
    hours real,
    deliverables_id integer
);
     DROP TABLE internal.labor_burn;
       internal         airsci    false    11            �            1259    16959    labor_burn_labor_burn_id_seq    SEQUENCE     �   CREATE SEQUENCE internal.labor_burn_labor_burn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 5   DROP SEQUENCE internal.labor_burn_labor_burn_id_seq;
       internal       airsci    false    223    11            �           0    0    labor_burn_labor_burn_id_seq    SEQUENCE OWNED BY     a   ALTER SEQUENCE internal.labor_burn_labor_burn_id_seq OWNED BY internal.labor_burn.labor_burn_id;
            internal       airsci    false    224            �            1259    16961    non_labor_burn    TABLE     �   CREATE TABLE internal.non_labor_burn (
    non_labor_burn_id bigint NOT NULL,
    subtask_breakdown_id integer,
    dollars real,
    deliverables_id integer
);
 $   DROP TABLE internal.non_labor_burn;
       internal         airsci    false    11            �            1259    16964 $   non_labor_burn_non_labor_burn_id_seq    SEQUENCE     �   CREATE SEQUENCE internal.non_labor_burn_non_labor_burn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 =   DROP SEQUENCE internal.non_labor_burn_non_labor_burn_id_seq;
       internal       airsci    false    11    225            �           0    0 $   non_labor_burn_non_labor_burn_id_seq    SEQUENCE OWNED BY     q   ALTER SEQUENCE internal.non_labor_burn_non_labor_burn_id_seq OWNED BY internal.non_labor_burn.non_labor_burn_id;
            internal       airsci    false    226            �            1259    16966    travel_burn    TABLE     �   CREATE TABLE internal.travel_burn (
    travel_burn_id bigint NOT NULL,
    subtask_breakdown_id integer,
    origin text,
    destination text,
    auto real,
    lodging real,
    meals real,
    days real,
    deliverables_id integer
);
 !   DROP TABLE internal.travel_burn;
       internal         airsci    false    11            �            1259    16972    travel_burn_travel_burn_id_seq    SEQUENCE     �   CREATE SEQUENCE internal.travel_burn_travel_burn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 7   DROP SEQUENCE internal.travel_burn_travel_burn_id_seq;
       internal       airsci    false    11    227            �           0    0    travel_burn_travel_burn_id_seq    SEQUENCE OWNED BY     e   ALTER SEQUENCE internal.travel_burn_travel_burn_id_seq OWNED BY internal.travel_burn.travel_burn_id;
            internal       airsci    false    228            �            1259    16852 
   components    TABLE     �   CREATE TABLE projects.components (
    component_id integer NOT NULL,
    subtask_id integer NOT NULL,
    component_num integer NOT NULL,
    "desc" text NOT NULL
);
     DROP TABLE projects.components;
       projects         airsci    false    9            �            1259    16989    deliverables_deliverable_id_seq    SEQUENCE     �   CREATE SEQUENCE projects.deliverables_deliverable_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 8   DROP SEQUENCE projects.deliverables_deliverable_id_seq;
       projects       airsci    false    208    9            �           0    0    deliverables_deliverable_id_seq    SEQUENCE OWNED BY     c   ALTER SEQUENCE projects.deliverables_deliverable_id_seq OWNED BY projects.components.component_id;
            projects       airsci    false    229            �            1259    17480    subtask_list    VIEW     �  CREATE VIEW projects.subtask_list AS
 SELECT pp.project_num,
    pt.task_num,
    ps.subtask_num,
    ibs."desc" AS status,
    ps.start_date,
    pt.task_id,
    ps.subtask_id
   FROM (((projects.subtasks ps
     JOIN projects.tasks pt ON ((pt.task_id = ps.task_id)))
     JOIN projects.projects pp ON ((pp.project_num = pt.project_num)))
     JOIN info.billable_status ibs ON (((ps.status * pt.status) = ibs.status_id)))
  ORDER BY ROW(pp.project_num, pt.task_num, ps.subtask_num);
 !   DROP VIEW projects.subtask_list;
       projects       airsci    false    213    213    213    213    213    214    214    214    214    217    217    230    9            �            1259    16997    subtasks_subtask_id_seq    SEQUENCE     �   CREATE SEQUENCE projects.subtasks_subtask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 0   DROP SEQUENCE projects.subtasks_subtask_id_seq;
       projects       airsci    false    9    213            �           0    0    subtasks_subtask_id_seq    SEQUENCE OWNED BY     W   ALTER SEQUENCE projects.subtasks_subtask_id_seq OWNED BY projects.subtasks.subtask_id;
            projects       airsci    false    231            �            1259    16999    task_orders_task_id_seq    SEQUENCE     �   CREATE SEQUENCE projects.task_orders_task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 0   DROP SEQUENCE projects.task_orders_task_id_seq;
       projects       airsci    false    214    9            �           0    0    task_orders_task_id_seq    SEQUENCE OWNED BY     Q   ALTER SEQUENCE projects.task_orders_task_id_seq OWNED BY projects.tasks.task_id;
            projects       airsci    false    232            �           2604    17225    labor labor_id    DEFAULT        ALTER TABLE ONLY budgets.labor ALTER COLUMN labor_id SET DEFAULT nextval('budgets.labor_budget_labor_budge_id_seq'::regclass);
 >   ALTER TABLE budgets.labor ALTER COLUMN labor_id DROP DEFAULT;
       budgets       airsci    false    202    201            �           2604    17226    nonlabor nonlabor_id    DEFAULT     �   ALTER TABLE ONLY budgets.nonlabor ALTER COLUMN nonlabor_id SET DEFAULT nextval('budgets.non_labor_budget_non_labor_budget_id_seq'::regclass);
 D   ALTER TABLE budgets.nonlabor ALTER COLUMN nonlabor_id DROP DEFAULT;
       budgets       airsci    false    210    209            �           2604    17227    travel trip_id    DEFAULT     �   ALTER TABLE ONLY budgets.travel ALTER COLUMN trip_id SET DEFAULT nextval('budgets.travel_budget_travel_budget_id_seq'::regclass);
 >   ALTER TABLE budgets.travel ALTER COLUMN trip_id DROP DEFAULT;
       budgets       airsci    false    215    212            �           2604    17228    billing_rates level_id    DEFAULT     �   ALTER TABLE ONLY info.billing_rates ALTER COLUMN level_id SET DEFAULT nextval('info.billing_rates_billing_rate_id_seq'::regclass);
 C   ALTER TABLE info.billing_rates ALTER COLUMN level_id DROP DEFAULT;
       info       airsci    false    218    203            �           2604    17229    personnel_info personnel_id    DEFAULT     �   ALTER TABLE ONLY info.personnel_info ALTER COLUMN personnel_id SET DEFAULT nextval('info."Personnel_personnel_id_seq"'::regclass);
 H   ALTER TABLE info.personnel_info ALTER COLUMN personnel_id DROP DEFAULT;
       info       airsci    false    216    204            �           2604    17546    travel travel_id    DEFAULT     p   ALTER TABLE ONLY info.travel ALTER COLUMN travel_id SET DEFAULT nextval('info.travel_travel_id_seq'::regclass);
 =   ALTER TABLE info.travel ALTER COLUMN travel_id DROP DEFAULT;
       info       airsci    false    247    244            �           2604    17569    travel_rates travel_rate_id    DEFAULT     �   ALTER TABLE ONLY info.travel_rates ALTER COLUMN travel_rate_id SET DEFAULT nextval('info.travel_rates_travel_rate_id_seq1'::regclass);
 H   ALTER TABLE info.travel_rates ALTER COLUMN travel_rate_id DROP DEFAULT;
       info       airsci    false    249    248            �           2604    17535    travel_type type_id    DEFAULT     v   ALTER TABLE ONLY info.travel_type ALTER COLUMN type_id SET DEFAULT nextval('info.travel_type_type_id_seq'::regclass);
 @   ALTER TABLE info.travel_type ALTER COLUMN type_id DROP DEFAULT;
       info       airsci    false    246    245            �           2604    17231    estimated estimated_id    DEFAULT     �   ALTER TABLE ONLY internal.estimated ALTER COLUMN estimated_id SET DEFAULT nextval('internal.estimated_estimated_id_seq'::regclass);
 G   ALTER TABLE internal.estimated ALTER COLUMN estimated_id DROP DEFAULT;
       internal       airsci    false    220    219            �           2604    17232    invoice invoice_id    DEFAULT     |   ALTER TABLE ONLY internal.invoice ALTER COLUMN invoice_id SET DEFAULT nextval('internal.invoice_invoice_id_seq'::regclass);
 C   ALTER TABLE internal.invoice ALTER COLUMN invoice_id DROP DEFAULT;
       internal       airsci    false    222    221            �           2604    17233    labor_burn labor_burn_id    DEFAULT     �   ALTER TABLE ONLY internal.labor_burn ALTER COLUMN labor_burn_id SET DEFAULT nextval('internal.labor_burn_labor_burn_id_seq'::regclass);
 I   ALTER TABLE internal.labor_burn ALTER COLUMN labor_burn_id DROP DEFAULT;
       internal       airsci    false    224    223            �           2604    17234     non_labor_burn non_labor_burn_id    DEFAULT     �   ALTER TABLE ONLY internal.non_labor_burn ALTER COLUMN non_labor_burn_id SET DEFAULT nextval('internal.non_labor_burn_non_labor_burn_id_seq'::regclass);
 Q   ALTER TABLE internal.non_labor_burn ALTER COLUMN non_labor_burn_id DROP DEFAULT;
       internal       airsci    false    226    225            �           2604    17235    travel_burn travel_burn_id    DEFAULT     �   ALTER TABLE ONLY internal.travel_burn ALTER COLUMN travel_burn_id SET DEFAULT nextval('internal.travel_burn_travel_burn_id_seq'::regclass);
 K   ALTER TABLE internal.travel_burn ALTER COLUMN travel_burn_id DROP DEFAULT;
       internal       airsci    false    228    227            �           2604    17241    components component_id    DEFAULT     �   ALTER TABLE ONLY projects.components ALTER COLUMN component_id SET DEFAULT nextval('projects.deliverables_deliverable_id_seq'::regclass);
 H   ALTER TABLE projects.components ALTER COLUMN component_id DROP DEFAULT;
       projects       airsci    false    229    208            �           2604    17239    subtasks subtask_id    DEFAULT     ~   ALTER TABLE ONLY projects.subtasks ALTER COLUMN subtask_id SET DEFAULT nextval('projects.subtasks_subtask_id_seq'::regclass);
 D   ALTER TABLE projects.subtasks ALTER COLUMN subtask_id DROP DEFAULT;
       projects       airsci    false    231    213            �           2604    17240    tasks task_id    DEFAULT     x   ALTER TABLE ONLY projects.tasks ALTER COLUMN task_id SET DEFAULT nextval('projects.task_orders_task_id_seq'::regclass);
 >   ALTER TABLE projects.tasks ALTER COLUMN task_id DROP DEFAULT;
       projects       airsci    false    232    214            �          0    16811    labor 
   TABLE DATA               U   COPY budgets.labor (labor_id, personnel_id, hours, component_id, "desc") FROM stdin;
    budgets       airsci    false    201   �_      �          0    16868    nonlabor 
   TABLE DATA               V   COPY budgets.nonlabor (nonlabor_id, subtask_id, cost, "desc", company_id) FROM stdin;
    budgets       airsci    false    209   u`      �          0    16884    travel 
   TABLE DATA               �   COPY budgets.travel (trip_id, air_travel_id, days, num_staff, num_trips, subtask_id, company_id, "desc", lodging, meals, mileage, num_rental_cars, "from", "to") FROM stdin;
    budgets       airsci    false    212   �`      �          0    17405    deactivations 
   TABLE DATA               K   COPY changes.deactivations (deactivation_id, subtask_id, date) FROM stdin;
    changes       airsci    false    240   �a      �          0    17317    labor 
   TABLE DATA               N   COPY changes.labor (labor_change_id, labor_id, value, package_id) FROM stdin;
    changes       airsci    false    236   �a      �          0    17322    nonlabor 
   TABLE DATA               W   COPY changes.nonlabor (nonlabor_change_id, nonlabor_id, value, package_id) FROM stdin;
    changes       airsci    false    237   b      �          0    17309    packages 
   TABLE DATA               F   COPY changes.packages (package_id, type_id, date, "desc") FROM stdin;
    changes       airsci    false    235   3b      �          0    17327    travel 
   TABLE DATA               O   COPY changes.travel (travel_change_id, trip_id, value, package_id) FROM stdin;
    changes       airsci    false    238   qb      �          0    17301    types 
   TABLE DATA               1   COPY changes.types (type_id, "desc") FROM stdin;
    changes       airsci    false    234   �b      �          0    16933    billable_status 
   TABLE DATA               :   COPY info.billable_status (status_id, "desc") FROM stdin;
    info       airsci    false    217   �b      �          0    16816    billing_rates 
   TABLE DATA               J   COPY info.billing_rates (level_id, rate, rate_id, start_date) FROM stdin;
    info       airsci    false    203   c      �          0    16829 	   companies 
   TABLE DATA               L   COPY info.companies (company_id, full_name, abrv_name, type_id) FROM stdin;
    info       airsci    false    205   �c      �          0    16835    company_type 
   TABLE DATA               ;   COPY info.company_type (type_id, abrv, "desc") FROM stdin;
    info       airsci    false    206   d      �          0    16841    level_types 
   TABLE DATA               A   COPY info.level_types (level_id, company_id, "desc") FROM stdin;
    info       airsci    false    207   sd      �          0    16819    personnel_info 
   TABLE DATA               v   COPY info.personnel_info (personnel_id, company_id, first_name, last_name, cell_phone, work_phone, email) FROM stdin;
    info       airsci    false    204   %e      �          0    17428    personnel_levels 
   TABLE DATA               `   COPY info.personnel_levels (personnel_id, level_id, start_date, personnel_level_id) FROM stdin;
    info       airsci    false    241   �e      �          0    17508    travel 
   TABLE DATA               G   COPY info.travel (type_id, origin, destination, travel_id) FROM stdin;
    info       airsci    false    244   Bf      �          0    17558    travel_rates 
   TABLE DATA               X   COPY info.travel_rates (rate, units, start_date, travel_rate_id, travel_id) FROM stdin;
    info       airsci    false    248   �f      �          0    17516    travel_type 
   TABLE DATA               4   COPY info.travel_type ("desc", type_id) FROM stdin;
    info       airsci    false    245   Cg      �          0    16943 	   estimated 
   TABLE DATA               ?   COPY internal.estimated (estimated_id, subtask_id) FROM stdin;
    internal       airsci    false    219   �g      �          0    16948    invoice 
   TABLE DATA               Y   COPY internal.invoice (invoice_id, subtask_id, class, company, personnel_id) FROM stdin;
    internal       airsci    false    221   �g      �          0    16956 
   labor_burn 
   TABLE DATA               q   COPY internal.labor_burn (labor_burn_id, subtask_breakdown_id, personnel_id, hours, deliverables_id) FROM stdin;
    internal       airsci    false    223   �g      �          0    16961    non_labor_burn 
   TABLE DATA               m   COPY internal.non_labor_burn (non_labor_burn_id, subtask_breakdown_id, dollars, deliverables_id) FROM stdin;
    internal       airsci    false    225   �g      �          0    16966    travel_burn 
   TABLE DATA               �   COPY internal.travel_burn (travel_burn_id, subtask_breakdown_id, origin, destination, auto, lodging, meals, days, deliverables_id) FROM stdin;
    internal       airsci    false    227   h      �          0    16852 
   components 
   TABLE DATA               W   COPY projects.components (component_id, subtask_id, component_num, "desc") FROM stdin;
    projects       airsci    false    208   #h      �          0    16991    projects 
   TABLE DATA               M   COPY projects.projects (project_num, "desc", status, start_date) FROM stdin;
    projects       airsci    false    230   }i      �          0    16907    subtasks 
   TABLE DATA               b   COPY projects.subtasks (subtask_id, task_id, status, "desc", subtask_num, start_date) FROM stdin;
    projects       airsci    false    213   �i      �          0    16913    tasks 
   TABLE DATA               Q   COPY projects.tasks (task_id, "desc", status, project_num, task_num) FROM stdin;
    projects       airsci    false    214   Qj      �           0    0    labor_budget_labor_budge_id_seq    SEQUENCE SET     O   SELECT pg_catalog.setval('budgets.labor_budget_labor_budge_id_seq', 21, true);
            budgets       airsci    false    202            �           0    0 (   non_labor_budget_non_labor_budget_id_seq    SEQUENCE SET     W   SELECT pg_catalog.setval('budgets.non_labor_budget_non_labor_budget_id_seq', 1, true);
            budgets       airsci    false    210            �           0    0 "   travel_budget_travel_budget_id_seq    SEQUENCE SET     Q   SELECT pg_catalog.setval('budgets.travel_budget_travel_budget_id_seq', 6, true);
            budgets       airsci    false    215            �           0    0    Personnel_personnel_id_seq    SEQUENCE SET     I   SELECT pg_catalog.setval('info."Personnel_personnel_id_seq"', 1, false);
            info       airsci    false    216            �           0    0 !   billing_rates_billing_rate_id_seq    SEQUENCE SET     N   SELECT pg_catalog.setval('info.billing_rates_billing_rate_id_seq', 1, false);
            info       airsci    false    218            �           0    0     travel_rates_travel_rate_id_seq1    SEQUENCE SET     L   SELECT pg_catalog.setval('info.travel_rates_travel_rate_id_seq1', 9, true);
            info       airsci    false    249            �           0    0    travel_travel_id_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('info.travel_travel_id_seq', 8, true);
            info       airsci    false    247            �           0    0    travel_type_type_id_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('info.travel_type_type_id_seq', 5, true);
            info       airsci    false    246            �           0    0    estimated_estimated_id_seq    SEQUENCE SET     K   SELECT pg_catalog.setval('internal.estimated_estimated_id_seq', 1, false);
            internal       airsci    false    220            �           0    0    invoice_invoice_id_seq    SEQUENCE SET     G   SELECT pg_catalog.setval('internal.invoice_invoice_id_seq', 1, false);
            internal       airsci    false    222            �           0    0    labor_burn_labor_burn_id_seq    SEQUENCE SET     M   SELECT pg_catalog.setval('internal.labor_burn_labor_burn_id_seq', 1, false);
            internal       airsci    false    224            �           0    0 $   non_labor_burn_non_labor_burn_id_seq    SEQUENCE SET     U   SELECT pg_catalog.setval('internal.non_labor_burn_non_labor_burn_id_seq', 1, false);
            internal       airsci    false    226            �           0    0    travel_burn_travel_burn_id_seq    SEQUENCE SET     O   SELECT pg_catalog.setval('internal.travel_burn_travel_burn_id_seq', 1, false);
            internal       airsci    false    228            �           0    0    deliverables_deliverable_id_seq    SEQUENCE SET     P   SELECT pg_catalog.setval('projects.deliverables_deliverable_id_seq', 1, false);
            projects       airsci    false    229            �           0    0    subtasks_subtask_id_seq    SEQUENCE SET     H   SELECT pg_catalog.setval('projects.subtasks_subtask_id_seq', 1, false);
            projects       airsci    false    231            �           0    0    task_orders_task_id_seq    SEQUENCE SET     H   SELECT pg_catalog.setval('projects.task_orders_task_id_seq', 1, false);
            projects       airsci    false    232            �           2606    17019    labor labor_budget_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY budgets.labor
    ADD CONSTRAINT labor_budget_pkey PRIMARY KEY (labor_id);
 B   ALTER TABLE ONLY budgets.labor DROP CONSTRAINT labor_budget_pkey;
       budgets         airsci    false    201            �           2606    17021    nonlabor non_labor_budget_pkey 
   CONSTRAINT     f   ALTER TABLE ONLY budgets.nonlabor
    ADD CONSTRAINT non_labor_budget_pkey PRIMARY KEY (nonlabor_id);
 I   ALTER TABLE ONLY budgets.nonlabor DROP CONSTRAINT non_labor_budget_pkey;
       budgets         airsci    false    209            �           2606    17023    travel travel_budget_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_budget_pkey PRIMARY KEY (trip_id);
 D   ALTER TABLE ONLY budgets.travel DROP CONSTRAINT travel_budget_pkey;
       budgets         airsci    false    212            �           2606    17316    packages change_packages_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY changes.packages
    ADD CONSTRAINT change_packages_pkey PRIMARY KEY (package_id);
 H   ALTER TABLE ONLY changes.packages DROP CONSTRAINT change_packages_pkey;
       changes         airsci    false    235            �           2606    17308    types change_type_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY changes.types
    ADD CONSTRAINT change_type_pkey PRIMARY KEY (type_id);
 A   ALTER TABLE ONLY changes.types DROP CONSTRAINT change_type_pkey;
       changes         airsci    false    234            �           2606    17409     deactivations deactivations_pkey 
   CONSTRAINT     l   ALTER TABLE ONLY changes.deactivations
    ADD CONSTRAINT deactivations_pkey PRIMARY KEY (deactivation_id);
 K   ALTER TABLE ONLY changes.deactivations DROP CONSTRAINT deactivations_pkey;
       changes         airsci    false    240            �           2606    17321    labor labor_changes_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY changes.labor
    ADD CONSTRAINT labor_changes_pkey PRIMARY KEY (labor_change_id);
 C   ALTER TABLE ONLY changes.labor DROP CONSTRAINT labor_changes_pkey;
       changes         airsci    false    236            �           2606    17326    nonlabor nonlabor_changes_pkey 
   CONSTRAINT     m   ALTER TABLE ONLY changes.nonlabor
    ADD CONSTRAINT nonlabor_changes_pkey PRIMARY KEY (nonlabor_change_id);
 I   ALTER TABLE ONLY changes.nonlabor DROP CONSTRAINT nonlabor_changes_pkey;
       changes         airsci    false    237            �           2606    17331    travel travel_changes_pkey 
   CONSTRAINT     g   ALTER TABLE ONLY changes.travel
    ADD CONSTRAINT travel_changes_pkey PRIMARY KEY (travel_change_id);
 E   ALTER TABLE ONLY changes.travel DROP CONSTRAINT travel_changes_pkey;
       changes         airsci    false    238            �           2606    17025    personnel_info Personnel_pkey 
   CONSTRAINT     e   ALTER TABLE ONLY info.personnel_info
    ADD CONSTRAINT "Personnel_pkey" PRIMARY KEY (personnel_id);
 G   ALTER TABLE ONLY info.personnel_info DROP CONSTRAINT "Personnel_pkey";
       info         airsci    false    204            �           2606    17027    companies companies_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY info.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (company_id);
 @   ALTER TABLE ONLY info.companies DROP CONSTRAINT companies_pkey;
       info         airsci    false    205            �           2606    17029    company_type company_type_pkey 
   CONSTRAINT     _   ALTER TABLE ONLY info.company_type
    ADD CONSTRAINT company_type_pkey PRIMARY KEY (type_id);
 F   ALTER TABLE ONLY info.company_type DROP CONSTRAINT company_type_pkey;
       info         airsci    false    206            �           2606    17432 %   personnel_levels personnel_level_pkey 
   CONSTRAINT     q   ALTER TABLE ONLY info.personnel_levels
    ADD CONSTRAINT personnel_level_pkey PRIMARY KEY (personnel_level_id);
 M   ALTER TABLE ONLY info.personnel_levels DROP CONSTRAINT personnel_level_pkey;
       info         airsci    false    241            �           2606    17031 $   level_types professional_levels_pkey 
   CONSTRAINT     f   ALTER TABLE ONLY info.level_types
    ADD CONSTRAINT professional_levels_pkey PRIMARY KEY (level_id);
 L   ALTER TABLE ONLY info.level_types DROP CONSTRAINT professional_levels_pkey;
       info         airsci    false    207            �           2606    17033    billing_rates rates_pkey 
   CONSTRAINT     Y   ALTER TABLE ONLY info.billing_rates
    ADD CONSTRAINT rates_pkey PRIMARY KEY (rate_id);
 @   ALTER TABLE ONLY info.billing_rates DROP CONSTRAINT rates_pkey;
       info         airsci    false    203            �           2606    17035    billable_status status_pkey 
   CONSTRAINT     ^   ALTER TABLE ONLY info.billable_status
    ADD CONSTRAINT status_pkey PRIMARY KEY (status_id);
 C   ALTER TABLE ONLY info.billable_status DROP CONSTRAINT status_pkey;
       info         airsci    false    217            �           2606    17554    travel travel_pkey 
   CONSTRAINT     U   ALTER TABLE ONLY info.travel
    ADD CONSTRAINT travel_pkey PRIMARY KEY (travel_id);
 :   ALTER TABLE ONLY info.travel DROP CONSTRAINT travel_pkey;
       info         airsci    false    244            �           2606    17577    travel_rates travel_rate_pkey 
   CONSTRAINT     e   ALTER TABLE ONLY info.travel_rates
    ADD CONSTRAINT travel_rate_pkey PRIMARY KEY (travel_rate_id);
 E   ALTER TABLE ONLY info.travel_rates DROP CONSTRAINT travel_rate_pkey;
       info         airsci    false    248            �           2606    17543    travel_type travel_type_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY info.travel_type
    ADD CONSTRAINT travel_type_pkey PRIMARY KEY (type_id);
 D   ALTER TABLE ONLY info.travel_type DROP CONSTRAINT travel_type_pkey;
       info         airsci    false    245            �           2606    17041    estimated estimated_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY internal.estimated
    ADD CONSTRAINT estimated_pkey PRIMARY KEY (estimated_id);
 D   ALTER TABLE ONLY internal.estimated DROP CONSTRAINT estimated_pkey;
       internal         airsci    false    219            �           2606    17043    invoice invoice_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY internal.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (invoice_id);
 @   ALTER TABLE ONLY internal.invoice DROP CONSTRAINT invoice_pkey;
       internal         airsci    false    221            �           2606    17045    labor_burn labor_burn_pkey 
   CONSTRAINT     e   ALTER TABLE ONLY internal.labor_burn
    ADD CONSTRAINT labor_burn_pkey PRIMARY KEY (labor_burn_id);
 F   ALTER TABLE ONLY internal.labor_burn DROP CONSTRAINT labor_burn_pkey;
       internal         airsci    false    223            �           2606    17047 "   non_labor_burn non_labor_burn_pkey 
   CONSTRAINT     q   ALTER TABLE ONLY internal.non_labor_burn
    ADD CONSTRAINT non_labor_burn_pkey PRIMARY KEY (non_labor_burn_id);
 N   ALTER TABLE ONLY internal.non_labor_burn DROP CONSTRAINT non_labor_burn_pkey;
       internal         airsci    false    225            �           2606    17049    travel_burn travel_burn_pkey 
   CONSTRAINT     h   ALTER TABLE ONLY internal.travel_burn
    ADD CONSTRAINT travel_burn_pkey PRIMARY KEY (travel_burn_id);
 H   ALTER TABLE ONLY internal.travel_burn DROP CONSTRAINT travel_burn_pkey;
       internal         airsci    false    227            �           2606    17057    components deliverables_pkey 
   CONSTRAINT     f   ALTER TABLE ONLY projects.components
    ADD CONSTRAINT deliverables_pkey PRIMARY KEY (component_id);
 H   ALTER TABLE ONLY projects.components DROP CONSTRAINT deliverables_pkey;
       projects         airsci    false    208            �           2606    17059    projects projects_pkey 
   CONSTRAINT     _   ALTER TABLE ONLY projects.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (project_num);
 B   ALTER TABLE ONLY projects.projects DROP CONSTRAINT projects_pkey;
       projects         airsci    false    230            �           2606    17061    subtasks subtasks_pkey 
   CONSTRAINT     ^   ALTER TABLE ONLY projects.subtasks
    ADD CONSTRAINT subtasks_pkey PRIMARY KEY (subtask_id);
 B   ALTER TABLE ONLY projects.subtasks DROP CONSTRAINT subtasks_pkey;
       projects         airsci    false    213            �           2606    17063    tasks task_orders_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY projects.tasks
    ADD CONSTRAINT task_orders_pkey PRIMARY KEY (task_id);
 B   ALTER TABLE ONLY projects.tasks DROP CONSTRAINT task_orders_pkey;
       projects         airsci    false    214            �           1259    17064    fki_non_labor_company_fkey    INDEX     V   CREATE INDEX fki_non_labor_company_fkey ON budgets.nonlabor USING btree (company_id);
 /   DROP INDEX budgets.fki_non_labor_company_fkey;
       budgets         airsci    false    209            �           1259    17065    fki_non_labor_subtask_fkey    INDEX     V   CREATE INDEX fki_non_labor_subtask_fkey ON budgets.nonlabor USING btree (subtask_id);
 /   DROP INDEX budgets.fki_non_labor_subtask_fkey;
       budgets         airsci    false    209            �           1259    17066    fki_travel_air_rate_fkey    INDEX     U   CREATE INDEX fki_travel_air_rate_fkey ON budgets.travel USING btree (air_travel_id);
 -   DROP INDEX budgets.fki_travel_air_rate_fkey;
       budgets         airsci    false    212            �           1259    17067    fki_travel_company_fkey    INDEX     Q   CREATE INDEX fki_travel_company_fkey ON budgets.travel USING btree (company_id);
 ,   DROP INDEX budgets.fki_travel_company_fkey;
       budgets         airsci    false    212            �           1259    17068    fki_travel_subtask_fkey    INDEX     Q   CREATE INDEX fki_travel_subtask_fkey ON budgets.travel USING btree (subtask_id);
 ,   DROP INDEX budgets.fki_travel_subtask_fkey;
       budgets         airsci    false    212            �           1259    17344    fki_change_type_fkey    INDEX     M   CREATE INDEX fki_change_type_fkey ON changes.packages USING btree (type_id);
 )   DROP INDEX changes.fki_change_type_fkey;
       changes         airsci    false    235            �           1259    17350    fki_labor_fkey    INDEX     E   CREATE INDEX fki_labor_fkey ON changes.labor USING btree (labor_id);
 #   DROP INDEX changes.fki_labor_fkey;
       changes         airsci    false    236            �           1259    17356    fki_labor_package_fkey    INDEX     O   CREATE INDEX fki_labor_package_fkey ON changes.labor USING btree (package_id);
 +   DROP INDEX changes.fki_labor_package_fkey;
       changes         airsci    false    236            �           1259    17362    fki_nonlabor_fkey    INDEX     N   CREATE INDEX fki_nonlabor_fkey ON changes.nonlabor USING btree (nonlabor_id);
 &   DROP INDEX changes.fki_nonlabor_fkey;
       changes         airsci    false    237            �           1259    17368    fki_nonlabor_package_fkey    INDEX     U   CREATE INDEX fki_nonlabor_package_fkey ON changes.nonlabor USING btree (package_id);
 .   DROP INDEX changes.fki_nonlabor_package_fkey;
       changes         airsci    false    237            �           1259    17374    fki_travel_fkey    INDEX     F   CREATE INDEX fki_travel_fkey ON changes.travel USING btree (trip_id);
 $   DROP INDEX changes.fki_travel_fkey;
       changes         airsci    false    238            �           1259    17380    fki_travel_package_fkey    INDEX     Q   CREATE INDEX fki_travel_package_fkey ON changes.travel USING btree (package_id);
 ,   DROP INDEX changes.fki_travel_package_fkey;
       changes         airsci    false    238            �           1259    17069    fki_companies_type_fkey    INDEX     N   CREATE INDEX fki_companies_type_fkey ON info.companies USING btree (type_id);
 )   DROP INDEX info.fki_companies_type_fkey;
       info         airsci    false    205            �           1259    17070    fki_levels_company_fkey    INDEX     S   CREATE INDEX fki_levels_company_fkey ON info.level_types USING btree (company_id);
 )   DROP INDEX info.fki_levels_company_fkey;
       info         airsci    false    207            �           1259    17444    fki_pl_level_fkey    INDEX     P   CREATE INDEX fki_pl_level_fkey ON info.personnel_levels USING btree (level_id);
 #   DROP INDEX info.fki_pl_level_fkey;
       info         airsci    false    241            �           1259    17438    fki_pl_personnel_fkey    INDEX     X   CREATE INDEX fki_pl_personnel_fkey ON info.personnel_levels USING btree (personnel_id);
 '   DROP INDEX info.fki_pl_personnel_fkey;
       info         airsci    false    241            �           1259    17583    fki_rate_travel_fkey    INDEX     P   CREATE INDEX fki_rate_travel_fkey ON info.travel_rates USING btree (travel_id);
 &   DROP INDEX info.fki_rate_travel_fkey;
       info         airsci    false    248            �           1259    17072    fki_rates_level_fkey    INDEX     P   CREATE INDEX fki_rates_level_fkey ON info.billing_rates USING btree (level_id);
 &   DROP INDEX info.fki_rates_level_fkey;
       info         airsci    false    203            �           1259    17589    fki_travel_type_fkey    INDEX     H   CREATE INDEX fki_travel_type_fkey ON info.travel USING btree (type_id);
 &   DROP INDEX info.fki_travel_type_fkey;
       info         airsci    false    244            �           1259    17074    fki_deliverables_subtask_fkey    INDEX     \   CREATE INDEX fki_deliverables_subtask_fkey ON projects.components USING btree (subtask_id);
 3   DROP INDEX projects.fki_deliverables_subtask_fkey;
       projects         airsci    false    208            �           1259    17075    fki_projects_status_fkey    INDEX     Q   CREATE INDEX fki_projects_status_fkey ON projects.projects USING btree (status);
 .   DROP INDEX projects.fki_projects_status_fkey;
       projects         airsci    false    230            �           1259    17076    fki_subtask_status_fkey    INDEX     P   CREATE INDEX fki_subtask_status_fkey ON projects.subtasks USING btree (status);
 -   DROP INDEX projects.fki_subtask_status_fkey;
       projects         airsci    false    213            �           1259    17077    fki_tasks_project_fkey    INDEX     Q   CREATE INDEX fki_tasks_project_fkey ON projects.tasks USING btree (project_num);
 ,   DROP INDEX projects.fki_tasks_project_fkey;
       projects         airsci    false    214            �           1259    17078    fki_tasks_status_fkey    INDEX     K   CREATE INDEX fki_tasks_status_fkey ON projects.tasks USING btree (status);
 +   DROP INDEX projects.fki_tasks_status_fkey;
       projects         airsci    false    214            �           2606    17079 $   labor labor_budget_personnel_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY budgets.labor
    ADD CONSTRAINT labor_budget_personnel_id_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);
 O   ALTER TABLE ONLY budgets.labor DROP CONSTRAINT labor_budget_personnel_id_fkey;
       budgets       airsci    false    3236    204    201            �           2606    17084    labor labor_work_item_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY budgets.labor
    ADD CONSTRAINT labor_work_item_fkey FOREIGN KEY (component_id) REFERENCES projects.components(component_id);
 E   ALTER TABLE ONLY budgets.labor DROP CONSTRAINT labor_work_item_fkey;
       budgets       airsci    false    208    3246    201            �           2606    17089    nonlabor non_labor_company_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY budgets.nonlabor
    ADD CONSTRAINT non_labor_company_fkey FOREIGN KEY (company_id) REFERENCES info.companies(company_id);
 J   ALTER TABLE ONLY budgets.nonlabor DROP CONSTRAINT non_labor_company_fkey;
       budgets       airsci    false    205    209    3238            �           2606    17094    nonlabor non_labor_subtask_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY budgets.nonlabor
    ADD CONSTRAINT non_labor_subtask_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);
 J   ALTER TABLE ONLY budgets.nonlabor DROP CONSTRAINT non_labor_subtask_fkey;
       budgets       airsci    false    3259    209    213            �           2606    17104    travel travel_company_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_company_fkey FOREIGN KEY (company_id) REFERENCES info.companies(company_id);
 E   ALTER TABLE ONLY budgets.travel DROP CONSTRAINT travel_company_fkey;
       budgets       airsci    false    212    205    3238            �           2606    17109    travel travel_subtask_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_subtask_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);
 E   ALTER TABLE ONLY budgets.travel DROP CONSTRAINT travel_subtask_fkey;
       budgets       airsci    false    213    3259    212                       2606    17339    packages change_type_fkey    FK CONSTRAINT        ALTER TABLE ONLY changes.packages
    ADD CONSTRAINT change_type_fkey FOREIGN KEY (type_id) REFERENCES changes.types(type_id);
 D   ALTER TABLE ONLY changes.packages DROP CONSTRAINT change_type_fkey;
       changes       airsci    false    3280    234    235                       2606    17345    labor labor_fkey    FK CONSTRAINT     x   ALTER TABLE ONLY changes.labor
    ADD CONSTRAINT labor_fkey FOREIGN KEY (labor_id) REFERENCES budgets.labor(labor_id);
 ;   ALTER TABLE ONLY changes.labor DROP CONSTRAINT labor_fkey;
       changes       airsci    false    236    3231    201                       2606    17351    labor labor_package_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY changes.labor
    ADD CONSTRAINT labor_package_fkey FOREIGN KEY (package_id) REFERENCES changes.packages(package_id);
 C   ALTER TABLE ONLY changes.labor DROP CONSTRAINT labor_package_fkey;
       changes       airsci    false    235    236    3282                       2606    17357    nonlabor nonlabor_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY changes.nonlabor
    ADD CONSTRAINT nonlabor_fkey FOREIGN KEY (nonlabor_id) REFERENCES budgets.nonlabor(nonlabor_id);
 A   ALTER TABLE ONLY changes.nonlabor DROP CONSTRAINT nonlabor_fkey;
       changes       airsci    false    237    209    3251            	           2606    17363    nonlabor nonlabor_package_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY changes.nonlabor
    ADD CONSTRAINT nonlabor_package_fkey FOREIGN KEY (package_id) REFERENCES changes.packages(package_id);
 I   ALTER TABLE ONLY changes.nonlabor DROP CONSTRAINT nonlabor_package_fkey;
       changes       airsci    false    3282    237    235            
           2606    17369    travel travel_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY changes.travel
    ADD CONSTRAINT travel_fkey FOREIGN KEY (trip_id) REFERENCES budgets.travel(trip_id);
 =   ALTER TABLE ONLY changes.travel DROP CONSTRAINT travel_fkey;
       changes       airsci    false    212    238    3256                       2606    17375    travel travel_package_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY changes.travel
    ADD CONSTRAINT travel_package_fkey FOREIGN KEY (package_id) REFERENCES changes.packages(package_id);
 E   ALTER TABLE ONLY changes.travel DROP CONSTRAINT travel_package_fkey;
       changes       airsci    false    235    3282    238            �           2606    17114 (   personnel_info Personnel_company_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.personnel_info
    ADD CONSTRAINT "Personnel_company_id_fkey" FOREIGN KEY (company_id) REFERENCES info.companies(company_id);
 R   ALTER TABLE ONLY info.personnel_info DROP CONSTRAINT "Personnel_company_id_fkey";
       info       airsci    false    204    3238    205            �           2606    17119    companies companies_type_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.companies
    ADD CONSTRAINT companies_type_fkey FOREIGN KEY (type_id) REFERENCES info.company_type(type_id);
 E   ALTER TABLE ONLY info.companies DROP CONSTRAINT companies_type_fkey;
       info       airsci    false    206    3241    205            �           2606    17124    level_types levels_company_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.level_types
    ADD CONSTRAINT levels_company_fkey FOREIGN KEY (company_id) REFERENCES info.companies(company_id);
 G   ALTER TABLE ONLY info.level_types DROP CONSTRAINT levels_company_fkey;
       info       airsci    false    3238    205    207                       2606    17439    personnel_levels pl_level_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.personnel_levels
    ADD CONSTRAINT pl_level_fkey FOREIGN KEY (level_id) REFERENCES info.level_types(level_id);
 F   ALTER TABLE ONLY info.personnel_levels DROP CONSTRAINT pl_level_fkey;
       info       airsci    false    3244    207    241                       2606    17433 "   personnel_levels pl_personnel_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.personnel_levels
    ADD CONSTRAINT pl_personnel_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);
 J   ALTER TABLE ONLY info.personnel_levels DROP CONSTRAINT pl_personnel_fkey;
       info       airsci    false    3236    204    241                       2606    17578    travel_rates rate_travel_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.travel_rates
    ADD CONSTRAINT rate_travel_fkey FOREIGN KEY (travel_id) REFERENCES info.travel(travel_id);
 E   ALTER TABLE ONLY info.travel_rates DROP CONSTRAINT rate_travel_fkey;
       info       airsci    false    248    244    3304            �           2606    17134    billing_rates rates_level_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY info.billing_rates
    ADD CONSTRAINT rates_level_fkey FOREIGN KEY (level_id) REFERENCES info.level_types(level_id);
 F   ALTER TABLE ONLY info.billing_rates DROP CONSTRAINT rates_level_fkey;
       info       airsci    false    203    3244    207                       2606    17584    travel travel_type_fkey    FK CONSTRAINT     }   ALTER TABLE ONLY info.travel
    ADD CONSTRAINT travel_type_fkey FOREIGN KEY (type_id) REFERENCES info.travel_type(type_id);
 ?   ALTER TABLE ONLY info.travel DROP CONSTRAINT travel_type_fkey;
       info       airsci    false    245    3306    244            �           2606    17139 #   estimated estimated_subtask_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.estimated
    ADD CONSTRAINT estimated_subtask_id_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);
 O   ALTER TABLE ONLY internal.estimated DROP CONSTRAINT estimated_subtask_id_fkey;
       internal       airsci    false    213    3259    219            �           2606    17144 !   invoice invoice_personnel_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.invoice
    ADD CONSTRAINT invoice_personnel_id_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);
 M   ALTER TABLE ONLY internal.invoice DROP CONSTRAINT invoice_personnel_id_fkey;
       internal       airsci    false    204    221    3236            �           2606    17149    invoice invoice_subtask_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.invoice
    ADD CONSTRAINT invoice_subtask_id_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);
 K   ALTER TABLE ONLY internal.invoice DROP CONSTRAINT invoice_subtask_id_fkey;
       internal       airsci    false    213    221    3259                        2606    17154 *   labor_burn labor_burn_deliverables_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.labor_burn
    ADD CONSTRAINT labor_burn_deliverables_id_fkey FOREIGN KEY (deliverables_id) REFERENCES projects.components(component_id);
 V   ALTER TABLE ONLY internal.labor_burn DROP CONSTRAINT labor_burn_deliverables_id_fkey;
       internal       airsci    false    208    223    3246                       2606    17159 '   labor_burn labor_burn_personnel_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.labor_burn
    ADD CONSTRAINT labor_burn_personnel_id_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);
 S   ALTER TABLE ONLY internal.labor_burn DROP CONSTRAINT labor_burn_personnel_id_fkey;
       internal       airsci    false    204    3236    223                       2606    17164 2   non_labor_burn non_labor_burn_deliverables_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.non_labor_burn
    ADD CONSTRAINT non_labor_burn_deliverables_id_fkey FOREIGN KEY (deliverables_id) REFERENCES projects.components(component_id);
 ^   ALTER TABLE ONLY internal.non_labor_burn DROP CONSTRAINT non_labor_burn_deliverables_id_fkey;
       internal       airsci    false    208    225    3246                       2606    17169 ,   travel_burn travel_burn_deliverables_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY internal.travel_burn
    ADD CONSTRAINT travel_burn_deliverables_id_fkey FOREIGN KEY (deliverables_id) REFERENCES projects.components(component_id);
 X   ALTER TABLE ONLY internal.travel_burn DROP CONSTRAINT travel_burn_deliverables_id_fkey;
       internal       airsci    false    208    227    3246            �           2606    17194 $   components deliverables_subtask_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY projects.components
    ADD CONSTRAINT deliverables_subtask_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);
 P   ALTER TABLE ONLY projects.components DROP CONSTRAINT deliverables_subtask_fkey;
       projects       airsci    false    208    213    3259                       2606    17199    projects projects_status_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY projects.projects
    ADD CONSTRAINT projects_status_fkey FOREIGN KEY (status) REFERENCES info.billable_status(status_id);
 I   ALTER TABLE ONLY projects.projects DROP CONSTRAINT projects_status_fkey;
       projects       airsci    false    230    217    3265            �           2606    17204    subtasks subtask_status_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY projects.subtasks
    ADD CONSTRAINT subtask_status_fkey FOREIGN KEY (status) REFERENCES info.billable_status(status_id);
 H   ALTER TABLE ONLY projects.subtasks DROP CONSTRAINT subtask_status_fkey;
       projects       airsci    false    217    213    3265            �           2606    17209    subtasks subtasks_task_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY projects.subtasks
    ADD CONSTRAINT subtasks_task_id_fkey FOREIGN KEY (task_id) REFERENCES projects.tasks(task_id);
 J   ALTER TABLE ONLY projects.subtasks DROP CONSTRAINT subtasks_task_id_fkey;
       projects       airsci    false    213    214    3263            �           2606    17214    tasks tasks_project_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY projects.tasks
    ADD CONSTRAINT tasks_project_fkey FOREIGN KEY (project_num) REFERENCES projects.projects(project_num);
 D   ALTER TABLE ONLY projects.tasks DROP CONSTRAINT tasks_project_fkey;
       projects       airsci    false    214    230    3278            �           2606    17219    tasks tasks_status_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY projects.tasks
    ADD CONSTRAINT tasks_status_fkey FOREIGN KEY (status) REFERENCES info.billable_status(status_id);
 C   ALTER TABLE ONLY projects.tasks DROP CONSTRAINT tasks_status_fkey;
       projects       airsci    false    3265    217    214            �   {   x�E��!D��(�$1L�ql���H?��FHH��~o�(�TC7�f�����t���Ȏ4��˴8zsia�A=P�%����Ҽ��na��h�sZB��d$x\�ye�x��i��R���*�      �   D   x�3�4�45 �м�Դ̼���Լ�̒b�`g �Z��������ZX�Y���W�i����� @[       �   �   x����j�@�ϛ���b�=���R/^�d6]������w�Z��b���i�����U����g
ݹ�@XYtȎ�%3�7��i�M`�SDx���~�uV���⋄䵃Ȥ��,��,D�}�c��7Z�hu��}�X��ƴ=W�|:U߭L��{��nI�9\�zUw�⟬��)W�i��˱�Sic��f=�_w�z�T����,�> �/��      �      x������ � �      �   *   x�3���5500�4�2�44�Ե�p�9�8u�!�=... �a      �      x�3�4��54 NC�=... "      �   .   x�3�4�420��50�54�L�H�-��QHIM+�K��K����� ��	�      �      x�3�4��5300�4����� ZU      �   <   x�3���O�L�LN,����2���+I-�K�Q)J�+NK-�2�tIM+�K��K����� ��      �      x�3���KL.�,K�2�t�0b���� `'�      �   |   x�U��0�S/f8@���:�"#�hy�0K�̏�r�֑�8����ccv�@��6���� ����ϊ@�
��'G+�V=5�;�w��<V,�Hѻ��=���Ǒ�Z�����1���3\      �   p   x�=�A
�0F��?��	�v/A���it�N`��4*�z�F/�B��1mn�X���1���$3�O�ٖ�Ở:�X7�ϖxz�WuA�k����C����+"�Vd&"      �   E   x�3���(��M�2�vr��M��Qp*-��K-.Vp�+I-*(�,N�2�����d�a������ �      �   �   x�e��
�@D��W���U��
��xYִꮤ���UA��df�&G/<�Vc��nv��ST,�٪/7����`���8F/.1V����z��:\�#2&����[�	g�Ċ(~��oR�#-�� ��TK��@*��Ax��}�%0��Hv�^��u�K      �   �   x�Mν
�@�z�a���VD��ml�dc/�\�����cv'A��􅼨�*<.������ה��5�,��8��ml?�ö�'w]�ŷ�U��ƙ��Z-�.�@&��br.�
)���*a����̱#Ǹ��B͈�ixwb�qiu��֘�&�o�؁F����f�L|      �   S   x�Uλ�@���%���K��#�*�Dó@7�e�����Y!��+4�:t|��
��*�	Y���l���v,�I�V      �   w   x�3��/*�I�K�Q����/Vp�KO�I-�Qpv�4�2�tI�+K-r�9���8��
���sS�J��z0��)�%�%g'�Rg�e��B�\�P��	�e�e
eYp��qqq l�0�      �   j   x�m�1�@�ݿپ���	� �����%g���z��}{����C.�k�ڼc

K7SQ�i���b�S��q��2x�X���Տi�S��Ϟ�,#.t      �   ?   x�s��L�(�4���OI��K�4�rN,RJ�+I��4��MM�)�4����IMLO�4����� �+k      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �   J  x�mQMK1='�b�
[���ul��P�Xċ���#�̒d[��][� �$��y�eh���1� �6�,q���W�rtk���L\Cj�Fb���K��X@�ʠr; �Q���,�����,�(,0u�؎82/}9����U�?C׈�;�a.	&\c�d�J5�S�UD�%s5��p�N)��)�	
�K�[#g)`6��<�%�_1�>��T���%J�Rߖ�wZ���K�3	�IR/n���������P->�Ug�PԘuF�M�c��r�����.�|�X��;��F�Y��^�\��q{x����I�п��� �!�ix;��~�L�Y      �   '   x�350��/O�+V�I�N�4�420��50"�=... �e%      �   �   x�M��
�0���)��&����PZG�#1/%�V��������t���ր�#m�����I
9oa������sL���ӡ�yʔƝ싽�P'Όa_�ҘZ�p!���+�����)��
ܐ�чX���G����86      �   :   x�3�����WpJ,��S�IMO�Q.-(�/*QN-*�LN-�4�450�42����� ��b     