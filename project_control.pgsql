CREATE TEMP TABLE labor_summary AS
    SELECT blb.labor_budget_id, blb.personnel_id, blb.hours,
        pd.subtask_id, ip.level_id, ibr.rate,
        blb.hours * ibr.rate AS total_cost, ips.abrv
    FROM budgets.labor_budget blb
    JOIN projects.deliverables pd ON blb.deliverables_id = pd.deliverables_id
    JOIN info.personnel ip ON blb.personnel_id = ip.personnel_id
    JOIN info.billing_rates ibr ON ip.level_id = ibr.level_id
    JOIN info.personnel_summary ips ON ip.personnel_id=ips.personnel_id;

CREATE TEMP TABLE nonlabor_summary AS
    SELECT bnb.*, ics.abrv 
    FROM budgets.nonlabor_budget bnb 
    JOIN info.company_summary ics USING(company_id);

CREATE TEMP TABLE travel_id_rollup AS
    WITH lodging AS (SELECT cost FROM info.travel_rates_nonair WHERE nonair_travel_rate_id=1), 
        car_rental AS (SELECT cost FROM info.travel_rates_nonair WHERE nonair_travel_rate_id=2), 
        meals AS (SELECT cost FROM info.travel_rates_nonair WHERE nonair_travel_rate_id=3), 
        mileage AS (SELECT cost FROM info.travel_rates_nonair WHERE nonair_travel_rate_id=4) 
    SELECT btb.travel_budget_id, btb.desc AS description, btb.num_trips, btb.num_staff, btb.days, btb.from, btb.to, 
        ics.abrv_name, ics.abrv, btb.subtask_id, 
        itra.origin AS air_orgin, itra.destination AS air_dest, itra.cost*btb.num_staff*btb.num_trips AS air_cost, 
        CASE WHEN btb.lodging THEN btb.num_trips*btb.num_staff*(btb.days-1)*lodging.cost
            ELSE 0
        END AS lodging_cost, 
        CASE WHEN btb.num_rental_cars>0 THEN btb.num_trips*btb.days*btb.num_rental_cars*car_rental.cost
            ELSE 0
        END AS car_rental_cost, 
        CASE WHEN btb.meals THEN btb.num_trips*btb.days*btb.num_staff*meals.cost
            ELSE 0
        END AS meals_cost, 
        CASE WHEN btb.mileage>0 THEN btb.num_trips*btb.mileage*mileage.cost
            ELSE 0
        END AS mileage_cost
    FROM budgets.travel_budget btb
    JOIN info.travel_rates_air itra ON btb.air_travel_rate_id=itra.air_travel_rate_id
    JOIN info.company_summary ics ON btb.company_id=ics.company_id 
    JOIN lodging ON 'true'
    JOIN car_rental ON 'true'
    JOIN meals ON 'true'
    JOIN mileage ON 'true';

CREATE TEMP TABLE travel_cost_totals AS
    SELECT travel_budget_id, 
    air_cost+lodging_cost+car_rental_cost+meals_cost+mileage_cost AS total_cost
    FROM travel_id_rollup;

CREATE TEMP TABLE travel_summary AS
    SELECT tcr.*, tct.total_cost
    FROM travel_id_rollup tcr 
    JOIN travel_cost_totals tct ON tcr.travel_budget_id=tct.travel_budget_id;

CREATE TEMP TABLE travel_subtask_rollup AS
    SELECT subtask_id, ROUND(SUM(total_cost)) AS total_cost
    FROM travel_summary
    GROUP BY subtask_id;

CREATE TEMP TABLE labor_subtask_rollup AS
    SELECT subtask_id, ROUND(SUM(total_cost)) AS total_cost
    FROM labor_summary
    GROUP BY subtask_id;

CREATE TEMP TABLE nonlabor_subtask_rollup AS
    SELECT subtask_id, ROUND(SUM(dollars)) AS total_cost
    FROM nonlabor_summary
    GROUP BY subtask_id;

CREATE TEMP TABLE subtask_cost_summary AS
    SELECT subtask_num, description, labor, travel, nonlabor, 
        labor+travel+nonlabor AS total
    FROM (
        SELECT ps.subtask_num, ps.desc AS description, 
            COALESCE(lsr.total_cost, 0) AS labor, 
            COALESCE(tsr.total_cost, 0) AS travel, 
            COALESCE(nsr.total_cost, 0) AS nonlabor 
        FROM projects.subtasks ps
        LEFT JOIN labor_subtask_rollup lsr USING(subtask_id)
        LEFT JOIN travel_subtask_rollup tsr USING(subtask_id)
        LEFT JOIN nonlabor_subtask_rollup nsr USING(subtask_id)
    ) pre_select
    ORDER BY subtask_num;

SELECT * FROM subtask_cost_summary;

CREATE TEMP TABLE utilization_rollup AS
    SELECT subtask_id, abrv, ROUND(SUM(total_cost)) AS total_cost
    FROM (
        SELECT subtask_id, abrv, ROUND(SUM(total_cost)) AS total_cost
        FROM travel_summary
        GROUP BY subtask_id, abrv
        UNION
        SELECT subtask_id, abrv, ROUND(SUM(total_cost)) AS total_cost
        FROM labor_summary
        GROUP BY subtask_id, abrv
        UNION
        SELECT subtask_id, abrv, ROUND(SUM(dollars)) AS total_cost
        FROM nonlabor_summary
        GROUP BY subtask_id, abrv
    ) second_rollup
    GROUP BY subtask_id, abrv;

SELECT * FROM utilization_rollup ORDER BY subtask_id;

CREATE TEMP TABLE subtask_total (
    subtask_num text
);
INSERT INTO subtask_total VALUES ('Total');
SELECT * FROM subtask_total;

CREATE TEMP TABLE utilization_summary AS
    WITH prm AS (SELECT * FROM utilization_rollup WHERE abrv='PRM'),
        sbe AS (SELECT * FROM utilization_rollup WHERE abrv='SBE'),
        obe AS (SELECT * FROM utilization_rollup WHERE abrv='OBE')
    SELECT subtask_num, 
        TO_CHAR(COALESCE(SUM(prm.total_cost)/SUM(scs.total), 0), '9.00') AS prm,
        TO_CHAR(COALESCE(SUM(sbe.total_cost)/SUM(scs.total), 0), '9.00') AS sbe,
        TO_CHAR(COALESCE(SUM(obe.total_cost)/SUM(scs.total), 0), '9.00') AS obe
    FROM projects.subtasks ps 
    LEFT JOIN prm USING(subtask_id) 
    LEFT JOIN sbe USING(subtask_id) 
    LEFT JOIN obe USING(subtask_id) 
    LEFT JOIN subtask_cost_summary scs USING(subtask_num)
    GROUP BY subtask_num 
    ORDER BY subtask_num;

SELECT * FROM utilization_summary;
SELECT * FROM utilization_rollup WHERE abrv='PRM';