--
-- PostgreSQL database dump
--

-- Dumped from database version 10.5
-- Dumped by pg_dump version 11.1

-- Started on 2019-01-29 08:30:24 PST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4 (class 2615 OID 16806)
-- Name: budgets; Type: SCHEMA; Schema: -; Owner: airsci
--

CREATE SCHEMA budgets;


ALTER SCHEMA budgets OWNER TO airsci;

--
-- TOC entry 12 (class 2615 OID 17300)
-- Name: changes; Type: SCHEMA; Schema: -; Owner: airsci
--

CREATE SCHEMA changes;


ALTER SCHEMA changes OWNER TO airsci;

--
-- TOC entry 6 (class 2615 OID 16807)
-- Name: info; Type: SCHEMA; Schema: -; Owner: airsci
--

CREATE SCHEMA info;


ALTER SCHEMA info OWNER TO airsci;

--
-- TOC entry 11 (class 2615 OID 16808)
-- Name: internal; Type: SCHEMA; Schema: -; Owner: airsci
--

CREATE SCHEMA internal;


ALTER SCHEMA internal OWNER TO airsci;

--
-- TOC entry 9 (class 2615 OID 16810)
-- Name: projects; Type: SCHEMA; Schema: -; Owner: airsci
--

CREATE SCHEMA projects;


ALTER SCHEMA projects OWNER TO airsci;

--
-- TOC entry 269 (class 1255 OID 17467)
-- Name: labor_rollup(date); Type: FUNCTION; Schema: budgets; Owner: airsci
--

CREATE FUNCTION budgets.labor_rollup(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, component_sum integer, total_cost real, personnel text, company character varying, type character, status text, labor_id integer, task_id integer, subtask_id integer, component_id integer)
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


ALTER FUNCTION budgets.labor_rollup(v_date date) OWNER TO airsci;

--
-- TOC entry 270 (class 1255 OID 17491)
-- Name: subtask_budget(date); Type: FUNCTION; Schema: budgets; Owner: airsci
--

CREATE FUNCTION budgets.subtask_budget(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, labor real, travel real, nonlabor real, total_cost real, status text, task_id integer, subtask_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH
labor AS (SELECT l.subtask_id, SUM(l.total_cost) AS cost
            FROM budgets.labor_rollup(v_date) l
            GROUP BY l.subtask_id),
travel AS (SELECT t.subtask_id, SUM(t.total_cost) AS cost
            FROM budgets.travel_rollup t
            GROUP BY t.subtask_id),
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


ALTER FUNCTION budgets.subtask_budget(v_date date) OWNER TO airsci;

--
-- TOC entry 268 (class 1255 OID 17503)
-- Name: subtask_budget_updated(date); Type: FUNCTION; Schema: budgets; Owner: airsci
--

CREATE FUNCTION budgets.subtask_budget_updated(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, labor real, nonlabor real, travel real, total real, subtask_id integer)
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


ALTER FUNCTION budgets.subtask_budget_updated(v_date date) OWNER TO airsci;

--
-- TOC entry 267 (class 1255 OID 17501)
-- Name: subtask_utilization(date); Type: FUNCTION; Schema: budgets; Owner: airsci
--

CREATE FUNCTION budgets.subtask_utilization(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, prm_dollars real, sbe_dollars real, obe_dollars real, prm_percent text, sbe_percent text, obe_percent text, subtask_id integer)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY
WITH 
ur AS (
        SELECT sq.subtask_id,
        sq.abrv,
        round(sum(sq.cost)) AS cost
        FROM ( SELECT travel_rollup.subtask_id,
                travel_rollup.abrv,
                round(sum(travel_rollup.total_cost)) AS cost
                FROM budgets.travel_rollup
                GROUP BY travel_rollup.subtask_id, travel_rollup.abrv
            UNION
                SELECT labor_rollup.subtask_id,
                labor_rollup.type,
                round(sum(labor_rollup.total_cost)) AS cost
                FROM (SELECT * FROM budgets.labor_rollup('2019-01-01')) labor_rollup
                GROUP BY labor_rollup.subtask_id, labor_rollup.type
            UNION
                SELECT nonlabor_rollup.subtask_id,
                nonlabor_rollup.abrv,
                round(sum(nonlabor_rollup.cost)::double precision) AS cost
                FROM budgets.nonlabor_rollup
                GROUP BY nonlabor_rollup.subtask_id, nonlabor_rollup.abrv) sq
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


ALTER FUNCTION budgets.subtask_utilization(v_date date) OWNER TO airsci;

--
-- TOC entry 271 (class 1255 OID 17507)
-- Name: subtask_utilization_updated(date); Type: FUNCTION; Schema: budgets; Owner: airsci
--

CREATE FUNCTION budgets.subtask_utilization_updated(v_date date) RETURNS TABLE(project_num integer, task_num integer, subtask_num integer, prm_dollars real, sbe_dollars real, obe_dollars real, prm_percent text, sbe_percent text, obe_percent text)
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


ALTER FUNCTION budgets.subtask_utilization_updated(v_date date) OWNER TO airsci;

--
-- TOC entry 262 (class 1255 OID 17404)
-- Name: subtask_changes(date); Type: FUNCTION; Schema: changes; Owner: airsci
--

CREATE FUNCTION changes.subtask_changes(v_date date) RETURNS TABLE(subtask_id integer, labor_change real, nonlabor_change real, travel_change real, total_change real)
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


ALTER FUNCTION changes.subtask_changes(v_date date) OWNER TO airsci;

--
-- TOC entry 266 (class 1255 OID 17427)
-- Name: subtask_utilization_changes(date); Type: FUNCTION; Schema: changes; Owner: airsci
--

CREATE FUNCTION changes.subtask_utilization_changes(v_date date) RETURNS TABLE(subtask_id integer, prm_change real, sbe_change real, obe_change real, total_change real)
    LANGUAGE plpgsql
    AS $$BEGIN
RETURN QUERY WITH
prm AS (SELECT clr.subtask_id, SUM(clr.value) AS change
        FROM changes.labor_rollup clr
        WHERE clr.date < v_date::date AND clr.type='PRM'
        GROUP BY clr.subtask_id),
sbe AS (SELECT clr.subtask_id, SUM(clr.value) AS change
       FROM changes.labor_rollup clr
        WHERE clr.date < v_date::date AND clr.type='SBE'
        GROUP BY clr.subtask_id),
obe AS (SELECT clr.subtask_id, SUM(clr.value) AS change
        FROM changes.labor_rollup clr
        WHERE clr.date < v_date::date AND clr.type='OBE'
        GROUP BY clr.subtask_id)
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


ALTER FUNCTION changes.subtask_utilization_changes(v_date date) OWNER TO airsci;

--
-- TOC entry 264 (class 1255 OID 17452)
-- Name: level_rates_snapshot(date); Type: FUNCTION; Schema: info; Owner: airsci
--

CREATE FUNCTION info.level_rates_snapshot(v_date date) RETURNS TABLE(level_id integer, rate real)
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


ALTER FUNCTION info.level_rates_snapshot(v_date date) OWNER TO airsci;

--
-- TOC entry 263 (class 1255 OID 17451)
-- Name: personnel_levels_snapshot(date); Type: FUNCTION; Schema: info; Owner: airsci
--

CREATE FUNCTION info.personnel_levels_snapshot(v_date date) RETURNS TABLE(personnel_id integer, level_id integer, level text)
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


ALTER FUNCTION info.personnel_levels_snapshot(v_date date) OWNER TO airsci;

--
-- TOC entry 265 (class 1255 OID 17466)
-- Name: personnel_snapshot(date); Type: FUNCTION; Schema: info; Owner: airsci
--

CREATE FUNCTION info.personnel_snapshot(v_date date) RETURNS TABLE(personnel_id integer, first_name text, last_name text, level text, company character varying, type character, rate real, company_id integer, level_id integer)
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


ALTER FUNCTION info.personnel_snapshot(v_date date) OWNER TO airsci;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 201 (class 1259 OID 16811)
-- Name: labor; Type: TABLE; Schema: budgets; Owner: airsci
--

CREATE TABLE budgets.labor (
    labor_id integer NOT NULL,
    personnel_id integer NOT NULL,
    hours real NOT NULL,
    component_id integer NOT NULL,
    "desc" text
);


ALTER TABLE budgets.labor OWNER TO airsci;

--
-- TOC entry 202 (class 1259 OID 16814)
-- Name: labor_budget_labor_budge_id_seq; Type: SEQUENCE; Schema: budgets; Owner: airsci
--

CREATE SEQUENCE budgets.labor_budget_labor_budge_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE budgets.labor_budget_labor_budge_id_seq OWNER TO airsci;

--
-- TOC entry 3506 (class 0 OID 0)
-- Dependencies: 202
-- Name: labor_budget_labor_budge_id_seq; Type: SEQUENCE OWNED BY; Schema: budgets; Owner: airsci
--

ALTER SEQUENCE budgets.labor_budget_labor_budge_id_seq OWNED BY budgets.labor.labor_id;


--
-- TOC entry 209 (class 1259 OID 16868)
-- Name: nonlabor; Type: TABLE; Schema: budgets; Owner: airsci
--

CREATE TABLE budgets.nonlabor (
    nonlabor_id integer NOT NULL,
    subtask_id integer NOT NULL,
    cost real NOT NULL,
    "desc" text NOT NULL,
    company_id integer NOT NULL
);


ALTER TABLE budgets.nonlabor OWNER TO airsci;

--
-- TOC entry 210 (class 1259 OID 16874)
-- Name: non_labor_budget_non_labor_budget_id_seq; Type: SEQUENCE; Schema: budgets; Owner: airsci
--

CREATE SEQUENCE budgets.non_labor_budget_non_labor_budget_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE budgets.non_labor_budget_non_labor_budget_id_seq OWNER TO airsci;

--
-- TOC entry 3507 (class 0 OID 0)
-- Dependencies: 210
-- Name: non_labor_budget_non_labor_budget_id_seq; Type: SEQUENCE OWNED BY; Schema: budgets; Owner: airsci
--

ALTER SEQUENCE budgets.non_labor_budget_non_labor_budget_id_seq OWNED BY budgets.nonlabor.nonlabor_id;


--
-- TOC entry 219 (class 1259 OID 16933)
-- Name: billable_status; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.billable_status (
    status_id integer NOT NULL,
    "desc" text
);


ALTER TABLE info.billable_status OWNER TO airsci;

--
-- TOC entry 205 (class 1259 OID 16829)
-- Name: companies; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.companies (
    company_id integer NOT NULL,
    full_name text,
    abrv_name character varying(8) NOT NULL,
    type_id integer NOT NULL
);


ALTER TABLE info.companies OWNER TO airsci;

--
-- TOC entry 206 (class 1259 OID 16835)
-- Name: company_type; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.company_type (
    type_id integer NOT NULL,
    abrv character(3) NOT NULL,
    "desc" text NOT NULL
);


ALTER TABLE info.company_type OWNER TO airsci;

--
-- TOC entry 211 (class 1259 OID 16876)
-- Name: company_summary; Type: VIEW; Schema: info; Owner: airsci
--

CREATE VIEW info.company_summary AS
 SELECT ic.company_id,
    ic.abrv_name,
    ict.type_id,
    ict.abrv
   FROM (info.companies ic
     JOIN info.company_type ict ON ((ic.type_id = ict.type_id)));


ALTER TABLE info.company_summary OWNER TO airsci;

--
-- TOC entry 233 (class 1259 OID 16991)
-- Name: projects; Type: TABLE; Schema: projects; Owner: airsci
--

CREATE TABLE projects.projects (
    project_num integer NOT NULL,
    "desc" text NOT NULL,
    status integer NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE projects.projects OWNER TO airsci;

--
-- TOC entry 215 (class 1259 OID 16907)
-- Name: subtasks; Type: TABLE; Schema: projects; Owner: airsci
--

CREATE TABLE projects.subtasks (
    subtask_id integer NOT NULL,
    task_id integer NOT NULL,
    status integer NOT NULL,
    "desc" text NOT NULL,
    subtask_num integer NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE projects.subtasks OWNER TO airsci;

--
-- TOC entry 216 (class 1259 OID 16913)
-- Name: tasks; Type: TABLE; Schema: projects; Owner: airsci
--

CREATE TABLE projects.tasks (
    task_id integer NOT NULL,
    "desc" text NOT NULL,
    status integer NOT NULL,
    project_num integer NOT NULL,
    task_num integer NOT NULL
);


ALTER TABLE projects.tasks OWNER TO airsci;

--
-- TOC entry 236 (class 1259 OID 17252)
-- Name: nonlabor_rollup; Type: VIEW; Schema: budgets; Owner: airsci
--

CREATE VIEW budgets.nonlabor_rollup WITH (security_barrier='false') AS
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


ALTER TABLE budgets.nonlabor_rollup OWNER TO airsci;

--
-- TOC entry 212 (class 1259 OID 16884)
-- Name: travel; Type: TABLE; Schema: budgets; Owner: airsci
--

CREATE TABLE budgets.travel (
    travel_id integer NOT NULL,
    air_travel_rate_id integer,
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


ALTER TABLE budgets.travel OWNER TO airsci;

--
-- TOC entry 217 (class 1259 OID 16929)
-- Name: travel_budget_travel_budget_id_seq; Type: SEQUENCE; Schema: budgets; Owner: airsci
--

CREATE SEQUENCE budgets.travel_budget_travel_budget_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE budgets.travel_budget_travel_budget_id_seq OWNER TO airsci;

--
-- TOC entry 3508 (class 0 OID 0)
-- Dependencies: 217
-- Name: travel_budget_travel_budget_id_seq; Type: SEQUENCE OWNED BY; Schema: budgets; Owner: airsci
--

ALTER SEQUENCE budgets.travel_budget_travel_budget_id_seq OWNED BY budgets.travel.travel_id;


--
-- TOC entry 213 (class 1259 OID 16890)
-- Name: travel_rates_air; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.travel_rates_air (
    air_travel_rate_id integer NOT NULL,
    origin text NOT NULL,
    destination text NOT NULL,
    cost real NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE info.travel_rates_air OWNER TO airsci;

--
-- TOC entry 214 (class 1259 OID 16896)
-- Name: travel_rates_nonair; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.travel_rates_nonair (
    nonair_travel_rate_id integer NOT NULL,
    "desc" text NOT NULL,
    cost real NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE info.travel_rates_nonair OWNER TO airsci;

--
-- TOC entry 237 (class 1259 OID 17257)
-- Name: travel_rollup; Type: VIEW; Schema: budgets; Owner: airsci
--

CREATE VIEW budgets.travel_rollup WITH (security_barrier='false') AS
 WITH travel_id_rollup AS (
         WITH lodging AS (
                 SELECT travel_rates_nonair.cost
                   FROM info.travel_rates_nonair
                  WHERE (travel_rates_nonair.nonair_travel_rate_id = 1)
                ), car_rental AS (
                 SELECT travel_rates_nonair.cost
                   FROM info.travel_rates_nonair
                  WHERE (travel_rates_nonair.nonair_travel_rate_id = 2)
                ), meals AS (
                 SELECT travel_rates_nonair.cost
                   FROM info.travel_rates_nonair
                  WHERE (travel_rates_nonair.nonair_travel_rate_id = 3)
                ), mileage AS (
                 SELECT travel_rates_nonair.cost
                   FROM info.travel_rates_nonair
                  WHERE (travel_rates_nonair.nonair_travel_rate_id = 4)
                )
         SELECT bt.travel_id,
            bt."desc" AS description,
            bt.num_trips,
            bt.num_staff,
            bt.days,
            bt."from",
            bt."to",
            ics.abrv_name,
            ics.abrv,
            bt.subtask_id,
            itra.origin AS air_orgin,
            itra.destination AS air_dest,
            ((itra.cost * (bt.num_staff)::double precision) * (bt.num_trips)::double precision) AS air_cost,
                CASE
                    WHEN bt.lodging THEN ((((bt.num_trips * bt.num_staff) * (bt.days - 1)))::double precision * lodging.cost)
                    ELSE (0)::double precision
                END AS lodging_cost,
                CASE
                    WHEN (bt.num_rental_cars > 0) THEN ((((bt.num_trips * bt.days) * bt.num_rental_cars))::double precision * car_rental.cost)
                    ELSE (0)::double precision
                END AS car_rental_cost,
                CASE
                    WHEN bt.meals THEN ((((bt.num_trips * bt.days) * bt.num_staff))::double precision * meals.cost)
                    ELSE (0)::double precision
                END AS meals_cost,
                CASE
                    WHEN (bt.mileage > (0)::double precision) THEN (((bt.num_trips)::double precision * bt.mileage) * mileage.cost)
                    ELSE (0)::double precision
                END AS mileage_cost
           FROM ((((((budgets.travel bt
             JOIN info.travel_rates_air itra ON ((bt.air_travel_rate_id = itra.air_travel_rate_id)))
             JOIN info.company_summary ics ON ((bt.company_id = ics.company_id)))
             JOIN lodging ON (true))
             JOIN car_rental ON (true))
             JOIN meals ON (true))
             JOIN mileage ON (true))
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
    tir.abrv_name,
    tir.abrv,
    travel_cost_totals.total_cost,
    ibs."desc" AS status,
    pt.task_id,
    ps.subtask_id,
    tir.travel_id
   FROM (((((travel_id_rollup tir
     JOIN projects.subtasks ps ON ((ps.subtask_id = tir.subtask_id)))
     JOIN projects.tasks pt ON ((pt.task_id = ps.task_id)))
     JOIN projects.projects pp ON ((pp.project_num = pt.project_num)))
     JOIN info.billable_status ibs ON ((ibs.status_id = ((pp.status * pt.status) * ps.status))))
     JOIN ( SELECT travel_id_rollup.travel_id,
            ((((travel_id_rollup.air_cost + travel_id_rollup.lodging_cost) + travel_id_rollup.car_rental_cost) + travel_id_rollup.meals_cost) + travel_id_rollup.mileage_cost) AS total_cost
           FROM travel_id_rollup) travel_cost_totals ON ((tir.travel_id = travel_cost_totals.travel_id)));


ALTER TABLE budgets.travel_rollup OWNER TO airsci;

--
-- TOC entry 246 (class 1259 OID 17405)
-- Name: deactivations; Type: TABLE; Schema: changes; Owner: airsci
--

CREATE TABLE changes.deactivations (
    deactivation_id integer NOT NULL,
    subtask_id integer NOT NULL,
    date date NOT NULL
);


ALTER TABLE changes.deactivations OWNER TO airsci;

--
-- TOC entry 240 (class 1259 OID 17317)
-- Name: labor; Type: TABLE; Schema: changes; Owner: airsci
--

CREATE TABLE changes.labor (
    labor_change_id integer NOT NULL,
    labor_id integer NOT NULL,
    value double precision NOT NULL,
    package_id integer NOT NULL
);


ALTER TABLE changes.labor OWNER TO airsci;

--
-- TOC entry 239 (class 1259 OID 17309)
-- Name: packages; Type: TABLE; Schema: changes; Owner: airsci
--

CREATE TABLE changes.packages (
    package_id integer NOT NULL,
    type_id integer NOT NULL,
    date date NOT NULL,
    "desc" text
);


ALTER TABLE changes.packages OWNER TO airsci;

--
-- TOC entry 238 (class 1259 OID 17301)
-- Name: types; Type: TABLE; Schema: changes; Owner: airsci
--

CREATE TABLE changes.types (
    type_id integer NOT NULL,
    "desc" text NOT NULL
);


ALTER TABLE changes.types OWNER TO airsci;

--
-- TOC entry 249 (class 1259 OID 17485)
-- Name: labor_rollup; Type: VIEW; Schema: changes; Owner: airsci
--

CREATE VIEW changes.labor_rollup AS
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


ALTER TABLE changes.labor_rollup OWNER TO airsci;

--
-- TOC entry 241 (class 1259 OID 17322)
-- Name: nonlabor; Type: TABLE; Schema: changes; Owner: airsci
--

CREATE TABLE changes.nonlabor (
    nonlabor_change_id integer NOT NULL,
    nonlabor_id integer NOT NULL,
    value double precision NOT NULL,
    package_id integer NOT NULL
);


ALTER TABLE changes.nonlabor OWNER TO airsci;

--
-- TOC entry 244 (class 1259 OID 17390)
-- Name: nonlabor_rollup; Type: VIEW; Schema: changes; Owner: airsci
--

CREATE VIEW changes.nonlabor_rollup AS
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


ALTER TABLE changes.nonlabor_rollup OWNER TO airsci;

--
-- TOC entry 243 (class 1259 OID 17334)
-- Name: package_summary; Type: VIEW; Schema: changes; Owner: airsci
--

CREATE VIEW changes.package_summary AS
 WITH total AS (
         SELECT labor.package_id,
            sum(labor.value) AS total
           FROM (changes.labor
             JOIN changes.packages USING (package_id))
          GROUP BY labor.package_id
        )
 SELECT cp.package_id,
    ct."desc",
    cp.date,
    total.total
   FROM ((changes.packages cp
     JOIN changes.types ct USING (type_id))
     JOIN total USING (package_id));


ALTER TABLE changes.package_summary OWNER TO airsci;

--
-- TOC entry 242 (class 1259 OID 17327)
-- Name: travel; Type: TABLE; Schema: changes; Owner: airsci
--

CREATE TABLE changes.travel (
    travel_change_id integer NOT NULL,
    travel_id integer NOT NULL,
    value double precision NOT NULL,
    package_id integer NOT NULL
);


ALTER TABLE changes.travel OWNER TO airsci;

--
-- TOC entry 245 (class 1259 OID 17395)
-- Name: travel_rollup; Type: VIEW; Schema: changes; Owner: airsci
--

CREATE VIEW changes.travel_rollup AS
 SELECT btr.project_num,
    btr.task_num,
    btr.subtask_num,
    ct."desc",
    cp.date,
    btr.abrv_name,
    btr.abrv,
    ctr.value,
    btr.task_id,
    btr.subtask_id,
    btr.travel_id,
    ctr.package_id
   FROM (((changes.travel ctr
     JOIN budgets.travel_rollup btr ON ((btr.travel_id = ctr.travel_id)))
     JOIN changes.packages cp ON ((cp.package_id = ctr.package_id)))
     JOIN changes.types ct ON ((ct.type_id = cp.type_id)))
  ORDER BY ROW(btr.project_num, btr.task_num, btr.subtask_num);


ALTER TABLE changes.travel_rollup OWNER TO airsci;

--
-- TOC entry 204 (class 1259 OID 16819)
-- Name: personnel_info; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.personnel_info (
    personnel_id integer NOT NULL,
    company_id integer NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    cell_phone text,
    work_phone text,
    email text
);


ALTER TABLE info.personnel_info OWNER TO airsci;

--
-- TOC entry 218 (class 1259 OID 16931)
-- Name: Personnel_personnel_id_seq; Type: SEQUENCE; Schema: info; Owner: airsci
--

CREATE SEQUENCE info."Personnel_personnel_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE info."Personnel_personnel_id_seq" OWNER TO airsci;

--
-- TOC entry 3509 (class 0 OID 0)
-- Dependencies: 218
-- Name: Personnel_personnel_id_seq; Type: SEQUENCE OWNED BY; Schema: info; Owner: airsci
--

ALTER SEQUENCE info."Personnel_personnel_id_seq" OWNED BY info.personnel_info.personnel_id;


--
-- TOC entry 203 (class 1259 OID 16816)
-- Name: billing_rates; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.billing_rates (
    level_id integer NOT NULL,
    rate real NOT NULL,
    rate_id integer NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE info.billing_rates OWNER TO airsci;

--
-- TOC entry 220 (class 1259 OID 16939)
-- Name: billing_rates_billing_rate_id_seq; Type: SEQUENCE; Schema: info; Owner: airsci
--

CREATE SEQUENCE info.billing_rates_billing_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE info.billing_rates_billing_rate_id_seq OWNER TO airsci;

--
-- TOC entry 3510 (class 0 OID 0)
-- Dependencies: 220
-- Name: billing_rates_billing_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: info; Owner: airsci
--

ALTER SEQUENCE info.billing_rates_billing_rate_id_seq OWNED BY info.billing_rates.level_id;


--
-- TOC entry 207 (class 1259 OID 16841)
-- Name: level_types; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.level_types (
    level_id integer NOT NULL,
    company_id integer NOT NULL,
    "desc" text
);


ALTER TABLE info.level_types OWNER TO airsci;

--
-- TOC entry 247 (class 1259 OID 17428)
-- Name: personnel_levels; Type: TABLE; Schema: info; Owner: airsci
--

CREATE TABLE info.personnel_levels (
    personnel_id integer NOT NULL,
    level_id integer NOT NULL,
    start_date date NOT NULL,
    personnel_level_id integer NOT NULL
);


ALTER TABLE info.personnel_levels OWNER TO airsci;

--
-- TOC entry 221 (class 1259 OID 16941)
-- Name: travel_rates_travel_rate_id_seq; Type: SEQUENCE; Schema: info; Owner: airsci
--

CREATE SEQUENCE info.travel_rates_travel_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE info.travel_rates_travel_rate_id_seq OWNER TO airsci;

--
-- TOC entry 3511 (class 0 OID 0)
-- Dependencies: 221
-- Name: travel_rates_travel_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: info; Owner: airsci
--

ALTER SEQUENCE info.travel_rates_travel_rate_id_seq OWNED BY info.travel_rates_air.air_travel_rate_id;


--
-- TOC entry 222 (class 1259 OID 16943)
-- Name: estimated; Type: TABLE; Schema: internal; Owner: airsci
--

CREATE TABLE internal.estimated (
    estimated_id bigint NOT NULL,
    subtask_id integer
);


ALTER TABLE internal.estimated OWNER TO airsci;

--
-- TOC entry 223 (class 1259 OID 16946)
-- Name: estimated_estimated_id_seq; Type: SEQUENCE; Schema: internal; Owner: airsci
--

CREATE SEQUENCE internal.estimated_estimated_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE internal.estimated_estimated_id_seq OWNER TO airsci;

--
-- TOC entry 3512 (class 0 OID 0)
-- Dependencies: 223
-- Name: estimated_estimated_id_seq; Type: SEQUENCE OWNED BY; Schema: internal; Owner: airsci
--

ALTER SEQUENCE internal.estimated_estimated_id_seq OWNED BY internal.estimated.estimated_id;


--
-- TOC entry 224 (class 1259 OID 16948)
-- Name: invoice; Type: TABLE; Schema: internal; Owner: airsci
--

CREATE TABLE internal.invoice (
    invoice_id bigint NOT NULL,
    subtask_id integer,
    class text,
    company text,
    personnel_id integer
);


ALTER TABLE internal.invoice OWNER TO airsci;

--
-- TOC entry 225 (class 1259 OID 16954)
-- Name: invoice_invoice_id_seq; Type: SEQUENCE; Schema: internal; Owner: airsci
--

CREATE SEQUENCE internal.invoice_invoice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE internal.invoice_invoice_id_seq OWNER TO airsci;

--
-- TOC entry 3513 (class 0 OID 0)
-- Dependencies: 225
-- Name: invoice_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: internal; Owner: airsci
--

ALTER SEQUENCE internal.invoice_invoice_id_seq OWNED BY internal.invoice.invoice_id;


--
-- TOC entry 226 (class 1259 OID 16956)
-- Name: labor_burn; Type: TABLE; Schema: internal; Owner: airsci
--

CREATE TABLE internal.labor_burn (
    labor_burn_id bigint NOT NULL,
    subtask_breakdown_id integer,
    personnel_id integer,
    hours real,
    deliverables_id integer
);


ALTER TABLE internal.labor_burn OWNER TO airsci;

--
-- TOC entry 227 (class 1259 OID 16959)
-- Name: labor_burn_labor_burn_id_seq; Type: SEQUENCE; Schema: internal; Owner: airsci
--

CREATE SEQUENCE internal.labor_burn_labor_burn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE internal.labor_burn_labor_burn_id_seq OWNER TO airsci;

--
-- TOC entry 3514 (class 0 OID 0)
-- Dependencies: 227
-- Name: labor_burn_labor_burn_id_seq; Type: SEQUENCE OWNED BY; Schema: internal; Owner: airsci
--

ALTER SEQUENCE internal.labor_burn_labor_burn_id_seq OWNED BY internal.labor_burn.labor_burn_id;


--
-- TOC entry 228 (class 1259 OID 16961)
-- Name: non_labor_burn; Type: TABLE; Schema: internal; Owner: airsci
--

CREATE TABLE internal.non_labor_burn (
    non_labor_burn_id bigint NOT NULL,
    subtask_breakdown_id integer,
    dollars real,
    deliverables_id integer
);


ALTER TABLE internal.non_labor_burn OWNER TO airsci;

--
-- TOC entry 229 (class 1259 OID 16964)
-- Name: non_labor_burn_non_labor_burn_id_seq; Type: SEQUENCE; Schema: internal; Owner: airsci
--

CREATE SEQUENCE internal.non_labor_burn_non_labor_burn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE internal.non_labor_burn_non_labor_burn_id_seq OWNER TO airsci;

--
-- TOC entry 3515 (class 0 OID 0)
-- Dependencies: 229
-- Name: non_labor_burn_non_labor_burn_id_seq; Type: SEQUENCE OWNED BY; Schema: internal; Owner: airsci
--

ALTER SEQUENCE internal.non_labor_burn_non_labor_burn_id_seq OWNED BY internal.non_labor_burn.non_labor_burn_id;


--
-- TOC entry 230 (class 1259 OID 16966)
-- Name: travel_burn; Type: TABLE; Schema: internal; Owner: airsci
--

CREATE TABLE internal.travel_burn (
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


ALTER TABLE internal.travel_burn OWNER TO airsci;

--
-- TOC entry 231 (class 1259 OID 16972)
-- Name: travel_burn_travel_burn_id_seq; Type: SEQUENCE; Schema: internal; Owner: airsci
--

CREATE SEQUENCE internal.travel_burn_travel_burn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE internal.travel_burn_travel_burn_id_seq OWNER TO airsci;

--
-- TOC entry 3516 (class 0 OID 0)
-- Dependencies: 231
-- Name: travel_burn_travel_burn_id_seq; Type: SEQUENCE OWNED BY; Schema: internal; Owner: airsci
--

ALTER SEQUENCE internal.travel_burn_travel_burn_id_seq OWNED BY internal.travel_burn.travel_burn_id;


--
-- TOC entry 208 (class 1259 OID 16852)
-- Name: components; Type: TABLE; Schema: projects; Owner: airsci
--

CREATE TABLE projects.components (
    component_id integer NOT NULL,
    subtask_id integer NOT NULL,
    component_num integer NOT NULL,
    "desc" text NOT NULL
);


ALTER TABLE projects.components OWNER TO airsci;

--
-- TOC entry 232 (class 1259 OID 16989)
-- Name: deliverables_deliverable_id_seq; Type: SEQUENCE; Schema: projects; Owner: airsci
--

CREATE SEQUENCE projects.deliverables_deliverable_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE projects.deliverables_deliverable_id_seq OWNER TO airsci;

--
-- TOC entry 3517 (class 0 OID 0)
-- Dependencies: 232
-- Name: deliverables_deliverable_id_seq; Type: SEQUENCE OWNED BY; Schema: projects; Owner: airsci
--

ALTER SEQUENCE projects.deliverables_deliverable_id_seq OWNED BY projects.components.component_id;


--
-- TOC entry 248 (class 1259 OID 17480)
-- Name: subtask_list; Type: VIEW; Schema: projects; Owner: airsci
--

CREATE VIEW projects.subtask_list AS
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


ALTER TABLE projects.subtask_list OWNER TO airsci;

--
-- TOC entry 234 (class 1259 OID 16997)
-- Name: subtasks_subtask_id_seq; Type: SEQUENCE; Schema: projects; Owner: airsci
--

CREATE SEQUENCE projects.subtasks_subtask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE projects.subtasks_subtask_id_seq OWNER TO airsci;

--
-- TOC entry 3518 (class 0 OID 0)
-- Dependencies: 234
-- Name: subtasks_subtask_id_seq; Type: SEQUENCE OWNED BY; Schema: projects; Owner: airsci
--

ALTER SEQUENCE projects.subtasks_subtask_id_seq OWNED BY projects.subtasks.subtask_id;


--
-- TOC entry 235 (class 1259 OID 16999)
-- Name: task_orders_task_id_seq; Type: SEQUENCE; Schema: projects; Owner: airsci
--

CREATE SEQUENCE projects.task_orders_task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE projects.task_orders_task_id_seq OWNER TO airsci;

--
-- TOC entry 3519 (class 0 OID 0)
-- Dependencies: 235
-- Name: task_orders_task_id_seq; Type: SEQUENCE OWNED BY; Schema: projects; Owner: airsci
--

ALTER SEQUENCE projects.task_orders_task_id_seq OWNED BY projects.tasks.task_id;


--
-- TOC entry 3207 (class 2604 OID 17225)
-- Name: labor labor_id; Type: DEFAULT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.labor ALTER COLUMN labor_id SET DEFAULT nextval('budgets.labor_budget_labor_budge_id_seq'::regclass);


--
-- TOC entry 3211 (class 2604 OID 17226)
-- Name: nonlabor nonlabor_id; Type: DEFAULT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.nonlabor ALTER COLUMN nonlabor_id SET DEFAULT nextval('budgets.non_labor_budget_non_labor_budget_id_seq'::regclass);


--
-- TOC entry 3212 (class 2604 OID 17227)
-- Name: travel travel_id; Type: DEFAULT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.travel ALTER COLUMN travel_id SET DEFAULT nextval('budgets.travel_budget_travel_budget_id_seq'::regclass);


--
-- TOC entry 3208 (class 2604 OID 17228)
-- Name: billing_rates level_id; Type: DEFAULT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.billing_rates ALTER COLUMN level_id SET DEFAULT nextval('info.billing_rates_billing_rate_id_seq'::regclass);


--
-- TOC entry 3209 (class 2604 OID 17229)
-- Name: personnel_info personnel_id; Type: DEFAULT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.personnel_info ALTER COLUMN personnel_id SET DEFAULT nextval('info."Personnel_personnel_id_seq"'::regclass);


--
-- TOC entry 3213 (class 2604 OID 17230)
-- Name: travel_rates_air air_travel_rate_id; Type: DEFAULT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.travel_rates_air ALTER COLUMN air_travel_rate_id SET DEFAULT nextval('info.travel_rates_travel_rate_id_seq'::regclass);


--
-- TOC entry 3216 (class 2604 OID 17231)
-- Name: estimated estimated_id; Type: DEFAULT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.estimated ALTER COLUMN estimated_id SET DEFAULT nextval('internal.estimated_estimated_id_seq'::regclass);


--
-- TOC entry 3217 (class 2604 OID 17232)
-- Name: invoice invoice_id; Type: DEFAULT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.invoice ALTER COLUMN invoice_id SET DEFAULT nextval('internal.invoice_invoice_id_seq'::regclass);


--
-- TOC entry 3218 (class 2604 OID 17233)
-- Name: labor_burn labor_burn_id; Type: DEFAULT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.labor_burn ALTER COLUMN labor_burn_id SET DEFAULT nextval('internal.labor_burn_labor_burn_id_seq'::regclass);


--
-- TOC entry 3219 (class 2604 OID 17234)
-- Name: non_labor_burn non_labor_burn_id; Type: DEFAULT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.non_labor_burn ALTER COLUMN non_labor_burn_id SET DEFAULT nextval('internal.non_labor_burn_non_labor_burn_id_seq'::regclass);


--
-- TOC entry 3220 (class 2604 OID 17235)
-- Name: travel_burn travel_burn_id; Type: DEFAULT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.travel_burn ALTER COLUMN travel_burn_id SET DEFAULT nextval('internal.travel_burn_travel_burn_id_seq'::regclass);


--
-- TOC entry 3210 (class 2604 OID 17241)
-- Name: components component_id; Type: DEFAULT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.components ALTER COLUMN component_id SET DEFAULT nextval('projects.deliverables_deliverable_id_seq'::regclass);


--
-- TOC entry 3214 (class 2604 OID 17239)
-- Name: subtasks subtask_id; Type: DEFAULT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.subtasks ALTER COLUMN subtask_id SET DEFAULT nextval('projects.subtasks_subtask_id_seq'::regclass);


--
-- TOC entry 3215 (class 2604 OID 17240)
-- Name: tasks task_id; Type: DEFAULT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.tasks ALTER COLUMN task_id SET DEFAULT nextval('projects.task_orders_task_id_seq'::regclass);


--
-- TOC entry 3459 (class 0 OID 16811)
-- Dependencies: 201
-- Data for Name: labor; Type: TABLE DATA; Schema: budgets; Owner: airsci
--

COPY budgets.labor (labor_id, personnel_id, hours, component_id, "desc") FROM stdin;
1	1	100	1	\N
2	1	40	2	\N
3	1	36	4	\N
4	2	50	1	\N
5	2	40	2	\N
6	6	40	2	\N
7	7	40	2	\N
8	1	100	5	\N
9	2	80	5	\N
10	4	40	5	\N
11	5	40	5	\N
12	6	160	5	\N
13	7	160	5	\N
14	8	80	5	\N
15	9	40	5	\N
16	10	80	5	\N
17	2	50	6	\N
18	1	80	7	\N
19	1	32	8	\N
20	2	32	9	\N
21	3	96	10	\N
\.


--
-- TOC entry 3467 (class 0 OID 16868)
-- Dependencies: 209
-- Data for Name: nonlabor; Type: TABLE DATA; Schema: budgets; Owner: airsci
--

COPY budgets.nonlabor (nonlabor_id, subtask_id, cost, "desc", company_id) FROM stdin;
1	2	50000	Undefined Sensits, CSCs, Met, Video Equipment	1
\.


--
-- TOC entry 3469 (class 0 OID 16884)
-- Dependencies: 212
-- Data for Name: travel; Type: TABLE DATA; Schema: budgets; Owner: airsci
--

COPY budgets.travel (travel_id, air_travel_rate_id, days, num_staff, num_trips, subtask_id, company_id, "desc", lodging, meals, mileage, num_rental_cars, "from", "to") FROM stdin;
1	2	4	2	1	1	1	Introductory Field Trip	t	t	0	1	Portland, OR	Lee Vining, CA
2	2	3	1	6	1	1	Internal strategy meetings	t	t	0	1	Portland, OR	Los Angeles, CA
3	2	3	1	3	1	1	Agency meetings	t	t	0	1	Portland, OR	Bishop, CA
4	4	4	1	1	1	5	Introductory field trip	t	t	0	1	Sacramento, CA	Lee Vining, CA
5	4	4	1	1	1	2	Introductory field trip	t	t	0	1	Sacramento, CA	Lee Vining, CA
6	2	5	1	1	2	1	Training of DWP staff for PI-SWERL sampling	t	t	0	1	Portland, OR	Lee Vining, CA
\.


--
-- TOC entry 3498 (class 0 OID 17405)
-- Dependencies: 246
-- Data for Name: deactivations; Type: TABLE DATA; Schema: changes; Owner: airsci
--

COPY changes.deactivations (deactivation_id, subtask_id, date) FROM stdin;
\.


--
-- TOC entry 3495 (class 0 OID 17317)
-- Dependencies: 240
-- Data for Name: labor; Type: TABLE DATA; Schema: changes; Owner: airsci
--

COPY changes.labor (labor_change_id, labor_id, value, package_id) FROM stdin;
1	9	-5000	1
2	13	-8000	1
3	12	-7000	1
\.


--
-- TOC entry 3496 (class 0 OID 17322)
-- Dependencies: 241
-- Data for Name: nonlabor; Type: TABLE DATA; Schema: changes; Owner: airsci
--

COPY changes.nonlabor (nonlabor_change_id, nonlabor_id, value, package_id) FROM stdin;
1	1	-10000	1
\.


--
-- TOC entry 3494 (class 0 OID 17309)
-- Dependencies: 239
-- Data for Name: packages; Type: TABLE DATA; Schema: changes; Owner: airsci
--

COPY changes.packages (package_id, type_id, date, "desc") FROM stdin;
1	3	2019-01-10	exampll defunding
\.


--
-- TOC entry 3497 (class 0 OID 17327)
-- Dependencies: 242
-- Data for Name: travel; Type: TABLE DATA; Schema: changes; Owner: airsci
--

COPY changes.travel (travel_change_id, travel_id, value, package_id) FROM stdin;
1	2	-6000	1
\.


--
-- TOC entry 3493 (class 0 OID 17301)
-- Dependencies: 238
-- Data for Name: types; Type: TABLE DATA; Schema: changes; Owner: airsci
--

COPY changes.types (type_id, "desc") FROM stdin;
1	Modification
2	Internal Transfer
3	Defunding
\.


--
-- TOC entry 3476 (class 0 OID 16933)
-- Dependencies: 219
-- Data for Name: billable_status; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.billable_status (status_id, "desc") FROM stdin;
0	Inactive
1	Active
\.


--
-- TOC entry 3461 (class 0 OID 16816)
-- Dependencies: 203
-- Data for Name: billing_rates; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.billing_rates (level_id, rate, rate_id, start_date) FROM stdin;
1	229	1	2019-01-01
2	195	2	2019-01-01
3	215	3	2019-01-01
4	169	4	2019-01-01
5	147	5	2019-01-01
6	124	6	2019-01-01
7	101	7	2019-01-01
8	90	8	2019-01-01
9	238.399994	9	2019-01-01
10	195.800003	10	2019-01-01
11	179.199997	11	2019-01-01
12	149.039993	12	2019-01-01
13	117.32	13	2019-01-01
1	500	14	2019-01-10
\.


--
-- TOC entry 3463 (class 0 OID 16829)
-- Dependencies: 205
-- Data for Name: companies; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.companies (company_id, full_name, abrv_name, type_id) FROM stdin;
1	Air Sciences Inc.	AirSci	1
2	Plantierra	Plant	2
3	Cordoba	Cordoba	2
5	Land IQ	LandIQ	2
6	Ann Sihler	AnnS	2
4	Formation	Form	3
\.


--
-- TOC entry 3464 (class 0 OID 16835)
-- Dependencies: 206
-- Data for Name: company_type; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.company_type (type_id, abrv, "desc") FROM stdin;
1	PRM	Prime
2	SBE	Small Business Enterprise
3	OBE	Other Business Enterprise
\.


--
-- TOC entry 3465 (class 0 OID 16841)
-- Dependencies: 207
-- Data for Name: level_types; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.level_types (level_id, company_id, "desc") FROM stdin;
1	1	Science Program Director
2	1	Principal I
3	1	Principal II
4	1	Associate
5	1	Senior
6	1	Staff
7	1	Assistant
8	6	Technical Writer
9	2	Principal Scientist
10	4	Senior Scientist II
11	5	Senior Scientist
12	3	Field Engineer 3
13	3	Field Engineer 1
\.


--
-- TOC entry 3462 (class 0 OID 16819)
-- Dependencies: 204
-- Data for Name: personnel_info; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.personnel_info (personnel_id, company_id, first_name, last_name, cell_phone, work_phone, email) FROM stdin;
1	1	Mark	Schaaf	\N	\N	\N
2	1	Maarten	Schreuder	\N	\N	\N
3	1	Julie	Lanthier	\N	\N	\N
4	1	Evan	Burgess	\N	\N	\N
5	1	Jeffery	Leadford	\N	\N	\N
6	5	Mica	Heilmann	\N	\N	\N
7	2	Jim	Richards	\N	\N	\N
9	4	Dane	Williams	\N	\N	\N
10	1	Kent	Norville	\N	\N	\N
8	3	Victor	Silvas	\N	\N	\N
\.


--
-- TOC entry 3499 (class 0 OID 17428)
-- Dependencies: 247
-- Data for Name: personnel_levels; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.personnel_levels (personnel_id, level_id, start_date, personnel_level_id) FROM stdin;
1	1	2019-01-01	1
2	2	2019-01-01	2
3	7	2019-01-01	3
4	5	2019-01-01	4
5	5	2019-01-01	5
6	11	2019-01-01	6
7	9	2019-01-01	7
8	13	2019-01-01	8
9	10	2019-01-01	9
10	2	2019-01-01	10
2	3	2019-01-10	11
\.


--
-- TOC entry 3470 (class 0 OID 16890)
-- Dependencies: 213
-- Data for Name: travel_rates_air; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.travel_rates_air (air_travel_rate_id, origin, destination, cost, start_date) FROM stdin;
2	Portland, OR	Los Angeles, CA	650	2019-01-01
3	Denver, CO	Los Angeles, CA	650	2019-01-01
4	Sacramento, CA	Los Angeles, CA	475	2019-01-01
5	San Fransisco, CA	Los Angeles, CA	350	2019-01-01
\.


--
-- TOC entry 3471 (class 0 OID 16896)
-- Dependencies: 214
-- Data for Name: travel_rates_nonair; Type: TABLE DATA; Schema: info; Owner: airsci
--

COPY info.travel_rates_nonair (nonair_travel_rate_id, "desc", cost, start_date) FROM stdin;
1	Lodging	150	2019-01-01
2	Car Rental	170	2019-01-01
3	Meals	60	2019-01-01
4	Mileage	0.535000026	2019-01-01
\.


--
-- TOC entry 3479 (class 0 OID 16943)
-- Dependencies: 222
-- Data for Name: estimated; Type: TABLE DATA; Schema: internal; Owner: airsci
--

COPY internal.estimated (estimated_id, subtask_id) FROM stdin;
\.


--
-- TOC entry 3481 (class 0 OID 16948)
-- Dependencies: 224
-- Data for Name: invoice; Type: TABLE DATA; Schema: internal; Owner: airsci
--

COPY internal.invoice (invoice_id, subtask_id, class, company, personnel_id) FROM stdin;
\.


--
-- TOC entry 3483 (class 0 OID 16956)
-- Dependencies: 226
-- Data for Name: labor_burn; Type: TABLE DATA; Schema: internal; Owner: airsci
--

COPY internal.labor_burn (labor_burn_id, subtask_breakdown_id, personnel_id, hours, deliverables_id) FROM stdin;
\.


--
-- TOC entry 3485 (class 0 OID 16961)
-- Dependencies: 228
-- Data for Name: non_labor_burn; Type: TABLE DATA; Schema: internal; Owner: airsci
--

COPY internal.non_labor_burn (non_labor_burn_id, subtask_breakdown_id, dollars, deliverables_id) FROM stdin;
\.


--
-- TOC entry 3487 (class 0 OID 16966)
-- Dependencies: 230
-- Data for Name: travel_burn; Type: TABLE DATA; Schema: internal; Owner: airsci
--

COPY internal.travel_burn (travel_burn_id, subtask_breakdown_id, origin, destination, auto, lodging, meals, days, deliverables_id) FROM stdin;
\.


--
-- TOC entry 3466 (class 0 OID 16852)
-- Dependencies: 208
-- Data for Name: components; Type: TABLE DATA; Schema: projects; Owner: airsci
--

COPY projects.components (component_id, subtask_id, component_num, "desc") FROM stdin;
1	1	1	General regulatory review and strategic planning support
2	1	2	One, two-day introductory field trip to Mono Basin
3	1	3	Up to six one-day internal strategic planning meeting in Los Angeles
4	1	4	Up to three one-day agency meetings in Bishop, Los Angeles, or Sacramento, CA
5	2	1	General technical review and analysis
6	2	2	Field data collection (soil samples, PI-SWERL), including PI-SWERL training
7	3	1	General Legal Support
8	4	1	Project management
9	4	2	Subcontractor management
10	4	3	Cost control and subcontractor invoicing
\.


--
-- TOC entry 3490 (class 0 OID 16991)
-- Dependencies: 233
-- Data for Name: projects; Type: TABLE DATA; Schema: projects; Owner: airsci
--

COPY projects.projects (project_num, "desc", status, start_date) FROM stdin;
500	Owens Lake	1	2019-01-01
\.


--
-- TOC entry 3472 (class 0 OID 16907)
-- Dependencies: 215
-- Data for Name: subtasks; Type: TABLE DATA; Schema: projects; Owner: airsci
--

COPY projects.subtasks (subtask_id, task_id, status, "desc", subtask_num, start_date) FROM stdin;
1	1	1	Regulatory Review and Strategic Planning Support	1	2019-01-01
2	1	1	Technical Review and Analysis	2	2019-01-01
3	1	1	General Legal Support	3	2019-01-01
4	1	1	Project Management	4	2019-01-01
\.


--
-- TOC entry 3473 (class 0 OID 16913)
-- Dependencies: 216
-- Data for Name: tasks; Type: TABLE DATA; Schema: projects; Owner: airsci
--

COPY projects.tasks (task_id, "desc", status, project_num, task_num) FROM stdin;
1	Mono Basin Legal Support Services	1	500	26
\.


--
-- TOC entry 3520 (class 0 OID 0)
-- Dependencies: 202
-- Name: labor_budget_labor_budge_id_seq; Type: SEQUENCE SET; Schema: budgets; Owner: airsci
--

SELECT pg_catalog.setval('budgets.labor_budget_labor_budge_id_seq', 21, true);


--
-- TOC entry 3521 (class 0 OID 0)
-- Dependencies: 210
-- Name: non_labor_budget_non_labor_budget_id_seq; Type: SEQUENCE SET; Schema: budgets; Owner: airsci
--

SELECT pg_catalog.setval('budgets.non_labor_budget_non_labor_budget_id_seq', 1, true);


--
-- TOC entry 3522 (class 0 OID 0)
-- Dependencies: 217
-- Name: travel_budget_travel_budget_id_seq; Type: SEQUENCE SET; Schema: budgets; Owner: airsci
--

SELECT pg_catalog.setval('budgets.travel_budget_travel_budget_id_seq', 6, true);


--
-- TOC entry 3523 (class 0 OID 0)
-- Dependencies: 218
-- Name: Personnel_personnel_id_seq; Type: SEQUENCE SET; Schema: info; Owner: airsci
--

SELECT pg_catalog.setval('info."Personnel_personnel_id_seq"', 1, false);


--
-- TOC entry 3524 (class 0 OID 0)
-- Dependencies: 220
-- Name: billing_rates_billing_rate_id_seq; Type: SEQUENCE SET; Schema: info; Owner: airsci
--

SELECT pg_catalog.setval('info.billing_rates_billing_rate_id_seq', 1, false);


--
-- TOC entry 3525 (class 0 OID 0)
-- Dependencies: 221
-- Name: travel_rates_travel_rate_id_seq; Type: SEQUENCE SET; Schema: info; Owner: airsci
--

SELECT pg_catalog.setval('info.travel_rates_travel_rate_id_seq', 1, false);


--
-- TOC entry 3526 (class 0 OID 0)
-- Dependencies: 223
-- Name: estimated_estimated_id_seq; Type: SEQUENCE SET; Schema: internal; Owner: airsci
--

SELECT pg_catalog.setval('internal.estimated_estimated_id_seq', 1, false);


--
-- TOC entry 3527 (class 0 OID 0)
-- Dependencies: 225
-- Name: invoice_invoice_id_seq; Type: SEQUENCE SET; Schema: internal; Owner: airsci
--

SELECT pg_catalog.setval('internal.invoice_invoice_id_seq', 1, false);


--
-- TOC entry 3528 (class 0 OID 0)
-- Dependencies: 227
-- Name: labor_burn_labor_burn_id_seq; Type: SEQUENCE SET; Schema: internal; Owner: airsci
--

SELECT pg_catalog.setval('internal.labor_burn_labor_burn_id_seq', 1, false);


--
-- TOC entry 3529 (class 0 OID 0)
-- Dependencies: 229
-- Name: non_labor_burn_non_labor_burn_id_seq; Type: SEQUENCE SET; Schema: internal; Owner: airsci
--

SELECT pg_catalog.setval('internal.non_labor_burn_non_labor_burn_id_seq', 1, false);


--
-- TOC entry 3530 (class 0 OID 0)
-- Dependencies: 231
-- Name: travel_burn_travel_burn_id_seq; Type: SEQUENCE SET; Schema: internal; Owner: airsci
--

SELECT pg_catalog.setval('internal.travel_burn_travel_burn_id_seq', 1, false);


--
-- TOC entry 3531 (class 0 OID 0)
-- Dependencies: 232
-- Name: deliverables_deliverable_id_seq; Type: SEQUENCE SET; Schema: projects; Owner: airsci
--

SELECT pg_catalog.setval('projects.deliverables_deliverable_id_seq', 1, false);


--
-- TOC entry 3532 (class 0 OID 0)
-- Dependencies: 234
-- Name: subtasks_subtask_id_seq; Type: SEQUENCE SET; Schema: projects; Owner: airsci
--

SELECT pg_catalog.setval('projects.subtasks_subtask_id_seq', 1, false);


--
-- TOC entry 3533 (class 0 OID 0)
-- Dependencies: 235
-- Name: task_orders_task_id_seq; Type: SEQUENCE SET; Schema: projects; Owner: airsci
--

SELECT pg_catalog.setval('projects.task_orders_task_id_seq', 1, false);


--
-- TOC entry 3222 (class 2606 OID 17019)
-- Name: labor labor_budget_pkey; Type: CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.labor
    ADD CONSTRAINT labor_budget_pkey PRIMARY KEY (labor_id);


--
-- TOC entry 3242 (class 2606 OID 17021)
-- Name: nonlabor non_labor_budget_pkey; Type: CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.nonlabor
    ADD CONSTRAINT non_labor_budget_pkey PRIMARY KEY (nonlabor_id);


--
-- TOC entry 3247 (class 2606 OID 17023)
-- Name: travel travel_budget_pkey; Type: CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_budget_pkey PRIMARY KEY (travel_id);


--
-- TOC entry 3277 (class 2606 OID 17316)
-- Name: packages change_packages_pkey; Type: CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.packages
    ADD CONSTRAINT change_packages_pkey PRIMARY KEY (package_id);


--
-- TOC entry 3275 (class 2606 OID 17308)
-- Name: types change_type_pkey; Type: CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.types
    ADD CONSTRAINT change_type_pkey PRIMARY KEY (type_id);


--
-- TOC entry 3292 (class 2606 OID 17409)
-- Name: deactivations deactivations_pkey; Type: CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.deactivations
    ADD CONSTRAINT deactivations_pkey PRIMARY KEY (deactivation_id);


--
-- TOC entry 3282 (class 2606 OID 17321)
-- Name: labor labor_changes_pkey; Type: CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.labor
    ADD CONSTRAINT labor_changes_pkey PRIMARY KEY (labor_change_id);


--
-- TOC entry 3286 (class 2606 OID 17326)
-- Name: nonlabor nonlabor_changes_pkey; Type: CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.nonlabor
    ADD CONSTRAINT nonlabor_changes_pkey PRIMARY KEY (nonlabor_change_id);


--
-- TOC entry 3290 (class 2606 OID 17331)
-- Name: travel travel_changes_pkey; Type: CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.travel
    ADD CONSTRAINT travel_changes_pkey PRIMARY KEY (travel_change_id);


--
-- TOC entry 3227 (class 2606 OID 17025)
-- Name: personnel_info Personnel_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.personnel_info
    ADD CONSTRAINT "Personnel_pkey" PRIMARY KEY (personnel_id);


--
-- TOC entry 3229 (class 2606 OID 17027)
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (company_id);


--
-- TOC entry 3232 (class 2606 OID 17029)
-- Name: company_type company_type_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.company_type
    ADD CONSTRAINT company_type_pkey PRIMARY KEY (type_id);


--
-- TOC entry 3296 (class 2606 OID 17432)
-- Name: personnel_levels personnel_level_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.personnel_levels
    ADD CONSTRAINT personnel_level_pkey PRIMARY KEY (personnel_level_id);


--
-- TOC entry 3235 (class 2606 OID 17031)
-- Name: level_types professional_levels_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.level_types
    ADD CONSTRAINT professional_levels_pkey PRIMARY KEY (level_id);


--
-- TOC entry 3225 (class 2606 OID 17033)
-- Name: billing_rates rates_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.billing_rates
    ADD CONSTRAINT rates_pkey PRIMARY KEY (rate_id);


--
-- TOC entry 3260 (class 2606 OID 17035)
-- Name: billable_status status_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.billable_status
    ADD CONSTRAINT status_pkey PRIMARY KEY (status_id);


--
-- TOC entry 3251 (class 2606 OID 17037)
-- Name: travel_rates_nonair travel_rates_nonair_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.travel_rates_nonair
    ADD CONSTRAINT travel_rates_nonair_pkey PRIMARY KEY (nonair_travel_rate_id);


--
-- TOC entry 3249 (class 2606 OID 17039)
-- Name: travel_rates_air travel_rates_pkey; Type: CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.travel_rates_air
    ADD CONSTRAINT travel_rates_pkey PRIMARY KEY (air_travel_rate_id);


--
-- TOC entry 3262 (class 2606 OID 17041)
-- Name: estimated estimated_pkey; Type: CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.estimated
    ADD CONSTRAINT estimated_pkey PRIMARY KEY (estimated_id);


--
-- TOC entry 3264 (class 2606 OID 17043)
-- Name: invoice invoice_pkey; Type: CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (invoice_id);


--
-- TOC entry 3266 (class 2606 OID 17045)
-- Name: labor_burn labor_burn_pkey; Type: CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.labor_burn
    ADD CONSTRAINT labor_burn_pkey PRIMARY KEY (labor_burn_id);


--
-- TOC entry 3268 (class 2606 OID 17047)
-- Name: non_labor_burn non_labor_burn_pkey; Type: CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.non_labor_burn
    ADD CONSTRAINT non_labor_burn_pkey PRIMARY KEY (non_labor_burn_id);


--
-- TOC entry 3270 (class 2606 OID 17049)
-- Name: travel_burn travel_burn_pkey; Type: CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.travel_burn
    ADD CONSTRAINT travel_burn_pkey PRIMARY KEY (travel_burn_id);


--
-- TOC entry 3237 (class 2606 OID 17057)
-- Name: components deliverables_pkey; Type: CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.components
    ADD CONSTRAINT deliverables_pkey PRIMARY KEY (component_id);


--
-- TOC entry 3273 (class 2606 OID 17059)
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (project_num);


--
-- TOC entry 3254 (class 2606 OID 17061)
-- Name: subtasks subtasks_pkey; Type: CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.subtasks
    ADD CONSTRAINT subtasks_pkey PRIMARY KEY (subtask_id);


--
-- TOC entry 3258 (class 2606 OID 17063)
-- Name: tasks task_orders_pkey; Type: CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.tasks
    ADD CONSTRAINT task_orders_pkey PRIMARY KEY (task_id);


--
-- TOC entry 3239 (class 1259 OID 17064)
-- Name: fki_non_labor_company_fkey; Type: INDEX; Schema: budgets; Owner: airsci
--

CREATE INDEX fki_non_labor_company_fkey ON budgets.nonlabor USING btree (company_id);


--
-- TOC entry 3240 (class 1259 OID 17065)
-- Name: fki_non_labor_subtask_fkey; Type: INDEX; Schema: budgets; Owner: airsci
--

CREATE INDEX fki_non_labor_subtask_fkey ON budgets.nonlabor USING btree (subtask_id);


--
-- TOC entry 3243 (class 1259 OID 17066)
-- Name: fki_travel_air_rate_fkey; Type: INDEX; Schema: budgets; Owner: airsci
--

CREATE INDEX fki_travel_air_rate_fkey ON budgets.travel USING btree (air_travel_rate_id);


--
-- TOC entry 3244 (class 1259 OID 17067)
-- Name: fki_travel_company_fkey; Type: INDEX; Schema: budgets; Owner: airsci
--

CREATE INDEX fki_travel_company_fkey ON budgets.travel USING btree (company_id);


--
-- TOC entry 3245 (class 1259 OID 17068)
-- Name: fki_travel_subtask_fkey; Type: INDEX; Schema: budgets; Owner: airsci
--

CREATE INDEX fki_travel_subtask_fkey ON budgets.travel USING btree (subtask_id);


--
-- TOC entry 3278 (class 1259 OID 17344)
-- Name: fki_change_type_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_change_type_fkey ON changes.packages USING btree (type_id);


--
-- TOC entry 3279 (class 1259 OID 17350)
-- Name: fki_labor_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_labor_fkey ON changes.labor USING btree (labor_id);


--
-- TOC entry 3280 (class 1259 OID 17356)
-- Name: fki_labor_package_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_labor_package_fkey ON changes.labor USING btree (package_id);


--
-- TOC entry 3283 (class 1259 OID 17362)
-- Name: fki_nonlabor_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_nonlabor_fkey ON changes.nonlabor USING btree (nonlabor_id);


--
-- TOC entry 3284 (class 1259 OID 17368)
-- Name: fki_nonlabor_package_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_nonlabor_package_fkey ON changes.nonlabor USING btree (package_id);


--
-- TOC entry 3287 (class 1259 OID 17374)
-- Name: fki_travel_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_travel_fkey ON changes.travel USING btree (travel_id);


--
-- TOC entry 3288 (class 1259 OID 17380)
-- Name: fki_travel_package_fkey; Type: INDEX; Schema: changes; Owner: airsci
--

CREATE INDEX fki_travel_package_fkey ON changes.travel USING btree (package_id);


--
-- TOC entry 3230 (class 1259 OID 17069)
-- Name: fki_companies_type_fkey; Type: INDEX; Schema: info; Owner: airsci
--

CREATE INDEX fki_companies_type_fkey ON info.companies USING btree (type_id);


--
-- TOC entry 3233 (class 1259 OID 17070)
-- Name: fki_levels_company_fkey; Type: INDEX; Schema: info; Owner: airsci
--

CREATE INDEX fki_levels_company_fkey ON info.level_types USING btree (company_id);


--
-- TOC entry 3293 (class 1259 OID 17444)
-- Name: fki_pl_level_fkey; Type: INDEX; Schema: info; Owner: airsci
--

CREATE INDEX fki_pl_level_fkey ON info.personnel_levels USING btree (level_id);


--
-- TOC entry 3294 (class 1259 OID 17438)
-- Name: fki_pl_personnel_fkey; Type: INDEX; Schema: info; Owner: airsci
--

CREATE INDEX fki_pl_personnel_fkey ON info.personnel_levels USING btree (personnel_id);


--
-- TOC entry 3223 (class 1259 OID 17072)
-- Name: fki_rates_level_fkey; Type: INDEX; Schema: info; Owner: airsci
--

CREATE INDEX fki_rates_level_fkey ON info.billing_rates USING btree (level_id);


--
-- TOC entry 3238 (class 1259 OID 17074)
-- Name: fki_deliverables_subtask_fkey; Type: INDEX; Schema: projects; Owner: airsci
--

CREATE INDEX fki_deliverables_subtask_fkey ON projects.components USING btree (subtask_id);


--
-- TOC entry 3271 (class 1259 OID 17075)
-- Name: fki_projects_status_fkey; Type: INDEX; Schema: projects; Owner: airsci
--

CREATE INDEX fki_projects_status_fkey ON projects.projects USING btree (status);


--
-- TOC entry 3252 (class 1259 OID 17076)
-- Name: fki_subtask_status_fkey; Type: INDEX; Schema: projects; Owner: airsci
--

CREATE INDEX fki_subtask_status_fkey ON projects.subtasks USING btree (status);


--
-- TOC entry 3255 (class 1259 OID 17077)
-- Name: fki_tasks_project_fkey; Type: INDEX; Schema: projects; Owner: airsci
--

CREATE INDEX fki_tasks_project_fkey ON projects.tasks USING btree (project_num);


--
-- TOC entry 3256 (class 1259 OID 17078)
-- Name: fki_tasks_status_fkey; Type: INDEX; Schema: projects; Owner: airsci
--

CREATE INDEX fki_tasks_status_fkey ON projects.tasks USING btree (status);


--
-- TOC entry 3297 (class 2606 OID 17079)
-- Name: labor labor_budget_personnel_id_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.labor
    ADD CONSTRAINT labor_budget_personnel_id_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);


--
-- TOC entry 3298 (class 2606 OID 17084)
-- Name: labor labor_work_item_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.labor
    ADD CONSTRAINT labor_work_item_fkey FOREIGN KEY (component_id) REFERENCES projects.components(component_id);


--
-- TOC entry 3304 (class 2606 OID 17089)
-- Name: nonlabor non_labor_company_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.nonlabor
    ADD CONSTRAINT non_labor_company_fkey FOREIGN KEY (company_id) REFERENCES info.companies(company_id);


--
-- TOC entry 3305 (class 2606 OID 17094)
-- Name: nonlabor non_labor_subtask_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.nonlabor
    ADD CONSTRAINT non_labor_subtask_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);


--
-- TOC entry 3306 (class 2606 OID 17099)
-- Name: travel travel_air_rate_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_air_rate_fkey FOREIGN KEY (air_travel_rate_id) REFERENCES info.travel_rates_air(air_travel_rate_id);


--
-- TOC entry 3307 (class 2606 OID 17104)
-- Name: travel travel_company_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_company_fkey FOREIGN KEY (company_id) REFERENCES info.companies(company_id);


--
-- TOC entry 3308 (class 2606 OID 17109)
-- Name: travel travel_subtask_fkey; Type: FK CONSTRAINT; Schema: budgets; Owner: airsci
--

ALTER TABLE ONLY budgets.travel
    ADD CONSTRAINT travel_subtask_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);


--
-- TOC entry 3321 (class 2606 OID 17339)
-- Name: packages change_type_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.packages
    ADD CONSTRAINT change_type_fkey FOREIGN KEY (type_id) REFERENCES changes.types(type_id);


--
-- TOC entry 3322 (class 2606 OID 17345)
-- Name: labor labor_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.labor
    ADD CONSTRAINT labor_fkey FOREIGN KEY (labor_id) REFERENCES budgets.labor(labor_id);


--
-- TOC entry 3323 (class 2606 OID 17351)
-- Name: labor labor_package_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.labor
    ADD CONSTRAINT labor_package_fkey FOREIGN KEY (package_id) REFERENCES changes.packages(package_id);


--
-- TOC entry 3324 (class 2606 OID 17357)
-- Name: nonlabor nonlabor_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.nonlabor
    ADD CONSTRAINT nonlabor_fkey FOREIGN KEY (nonlabor_id) REFERENCES budgets.nonlabor(nonlabor_id);


--
-- TOC entry 3325 (class 2606 OID 17363)
-- Name: nonlabor nonlabor_package_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.nonlabor
    ADD CONSTRAINT nonlabor_package_fkey FOREIGN KEY (package_id) REFERENCES changes.packages(package_id);


--
-- TOC entry 3326 (class 2606 OID 17369)
-- Name: travel travel_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.travel
    ADD CONSTRAINT travel_fkey FOREIGN KEY (travel_id) REFERENCES budgets.travel(travel_id);


--
-- TOC entry 3327 (class 2606 OID 17375)
-- Name: travel travel_package_fkey; Type: FK CONSTRAINT; Schema: changes; Owner: airsci
--

ALTER TABLE ONLY changes.travel
    ADD CONSTRAINT travel_package_fkey FOREIGN KEY (package_id) REFERENCES changes.packages(package_id);


--
-- TOC entry 3300 (class 2606 OID 17114)
-- Name: personnel_info Personnel_company_id_fkey; Type: FK CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.personnel_info
    ADD CONSTRAINT "Personnel_company_id_fkey" FOREIGN KEY (company_id) REFERENCES info.companies(company_id);


--
-- TOC entry 3301 (class 2606 OID 17119)
-- Name: companies companies_type_fkey; Type: FK CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.companies
    ADD CONSTRAINT companies_type_fkey FOREIGN KEY (type_id) REFERENCES info.company_type(type_id);


--
-- TOC entry 3302 (class 2606 OID 17124)
-- Name: level_types levels_company_fkey; Type: FK CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.level_types
    ADD CONSTRAINT levels_company_fkey FOREIGN KEY (company_id) REFERENCES info.companies(company_id);


--
-- TOC entry 3328 (class 2606 OID 17439)
-- Name: personnel_levels pl_level_fkey; Type: FK CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.personnel_levels
    ADD CONSTRAINT pl_level_fkey FOREIGN KEY (level_id) REFERENCES info.level_types(level_id);


--
-- TOC entry 3329 (class 2606 OID 17433)
-- Name: personnel_levels pl_personnel_fkey; Type: FK CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.personnel_levels
    ADD CONSTRAINT pl_personnel_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);


--
-- TOC entry 3299 (class 2606 OID 17134)
-- Name: billing_rates rates_level_fkey; Type: FK CONSTRAINT; Schema: info; Owner: airsci
--

ALTER TABLE ONLY info.billing_rates
    ADD CONSTRAINT rates_level_fkey FOREIGN KEY (level_id) REFERENCES info.level_types(level_id);


--
-- TOC entry 3313 (class 2606 OID 17139)
-- Name: estimated estimated_subtask_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.estimated
    ADD CONSTRAINT estimated_subtask_id_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);


--
-- TOC entry 3314 (class 2606 OID 17144)
-- Name: invoice invoice_personnel_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.invoice
    ADD CONSTRAINT invoice_personnel_id_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);


--
-- TOC entry 3315 (class 2606 OID 17149)
-- Name: invoice invoice_subtask_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.invoice
    ADD CONSTRAINT invoice_subtask_id_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);


--
-- TOC entry 3316 (class 2606 OID 17154)
-- Name: labor_burn labor_burn_deliverables_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.labor_burn
    ADD CONSTRAINT labor_burn_deliverables_id_fkey FOREIGN KEY (deliverables_id) REFERENCES projects.components(component_id);


--
-- TOC entry 3317 (class 2606 OID 17159)
-- Name: labor_burn labor_burn_personnel_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.labor_burn
    ADD CONSTRAINT labor_burn_personnel_id_fkey FOREIGN KEY (personnel_id) REFERENCES info.personnel_info(personnel_id);


--
-- TOC entry 3318 (class 2606 OID 17164)
-- Name: non_labor_burn non_labor_burn_deliverables_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.non_labor_burn
    ADD CONSTRAINT non_labor_burn_deliverables_id_fkey FOREIGN KEY (deliverables_id) REFERENCES projects.components(component_id);


--
-- TOC entry 3319 (class 2606 OID 17169)
-- Name: travel_burn travel_burn_deliverables_id_fkey; Type: FK CONSTRAINT; Schema: internal; Owner: airsci
--

ALTER TABLE ONLY internal.travel_burn
    ADD CONSTRAINT travel_burn_deliverables_id_fkey FOREIGN KEY (deliverables_id) REFERENCES projects.components(component_id);


--
-- TOC entry 3303 (class 2606 OID 17194)
-- Name: components deliverables_subtask_fkey; Type: FK CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.components
    ADD CONSTRAINT deliverables_subtask_fkey FOREIGN KEY (subtask_id) REFERENCES projects.subtasks(subtask_id);


--
-- TOC entry 3320 (class 2606 OID 17199)
-- Name: projects projects_status_fkey; Type: FK CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.projects
    ADD CONSTRAINT projects_status_fkey FOREIGN KEY (status) REFERENCES info.billable_status(status_id);


--
-- TOC entry 3309 (class 2606 OID 17204)
-- Name: subtasks subtask_status_fkey; Type: FK CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.subtasks
    ADD CONSTRAINT subtask_status_fkey FOREIGN KEY (status) REFERENCES info.billable_status(status_id);


--
-- TOC entry 3310 (class 2606 OID 17209)
-- Name: subtasks subtasks_task_id_fkey; Type: FK CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.subtasks
    ADD CONSTRAINT subtasks_task_id_fkey FOREIGN KEY (task_id) REFERENCES projects.tasks(task_id);


--
-- TOC entry 3311 (class 2606 OID 17214)
-- Name: tasks tasks_project_fkey; Type: FK CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.tasks
    ADD CONSTRAINT tasks_project_fkey FOREIGN KEY (project_num) REFERENCES projects.projects(project_num);


--
-- TOC entry 3312 (class 2606 OID 17219)
-- Name: tasks tasks_status_fkey; Type: FK CONSTRAINT; Schema: projects; Owner: airsci
--

ALTER TABLE ONLY projects.tasks
    ADD CONSTRAINT tasks_status_fkey FOREIGN KEY (status) REFERENCES info.billable_status(status_id);


--
-- TOC entry 3505 (class 0 OID 0)
-- Dependencies: 3
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: john
--

GRANT ALL ON SCHEMA public TO airsci;


-- Completed on 2019-01-29 08:30:25 PST

--
-- PostgreSQL database dump complete
--

