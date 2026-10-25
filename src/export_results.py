import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import pandas as pd
from sqlalchemy import text
from config import get_engine

engine = get_engine()

# Saari 10 queries yahan hain
queries = {
    "q01_headcount": """
        SELECT FORMAT(d.date_key, 'yyyy-MM') as Month, emp.plant, emp.department, COUNT(DISTINCT emp.emp_id) as Headcount 
        FROM warehouse.dim_employee emp 
        CROSS JOIN (SELECT DISTINCT date_key FROM warehouse.dim_date WHERE date_key IN ('2026-04-30', '2026-05-31', '2026-06-30', '2026-07-31', '2026-08-31', '2026-09-30')) d 
        WHERE emp.valid_from <= d.date_key AND emp.valid_to >= d.date_key 
        GROUP BY FORMAT(d.date_key, 'yyyy-MM'), emp.plant, emp.department
    """,
    "q02_attrition": """
        WITH Headcounts AS (
            SELECT FORMAT(date_key, 'yyyy-MM') as month, department, COUNT(DISTINCT emp_id) as emp_count
            FROM warehouse.dim_date d
            CROSS JOIN warehouse.dim_employee emp
            WHERE emp.valid_from <= d.date_key AND emp.valid_to >= d.date_key
            GROUP BY FORMAT(date_key, 'yyyy-MM'), department
        ),
        Separations AS (
            SELECT FORMAT(separation_date, 'yyyy-MM') as month, department, COUNT(DISTINCT emp_id) as sep_count
            FROM staging.employees
            WHERE separation_date IS NOT NULL
            GROUP BY FORMAT(separation_date, 'yyyy-MM'), department
        )
        SELECT h.month, h.department, h.emp_count as Avg_Headcount, ISNULL(s.sep_count, 0) as Separations,
        CAST(ISNULL(s.sep_count, 0) * 100.0 / NULLIF(h.emp_count, 0) AS DECIMAL(10,2)) as Attrition_Rate_Pct
        FROM Headcounts h
        LEFT JOIN Separations s ON h.month = s.month AND h.department = s.department
    """,
    "q03_absenteeism": """
        SELECT FORMAT(a.work_date, 'yyyy-MM') as Month, a.plant,
        COUNT(CASE WHEN a.status = 'Absent' THEN 1 END) as Absent_Days, COUNT(*) as Total_Working_Days,
        CAST(COUNT(CASE WHEN a.status = 'Absent' THEN 1 END) * 100.0 / COUNT(*) AS DECIMAL(10,2)) as Absenteeism_Pct
        FROM staging.attendance_daily a
        WHERE a.status NOT IN ('On Leave', 'Weekly Off', 'Holiday')
        GROUP BY FORMAT(a.work_date, 'yyyy-MM'), a.plant
    """,
    "q04_late_arrivals": """
        SELECT TOP 10 a.emp_id, e.full_name, e.department,
        SUM(CASE WHEN a.is_late = 1 THEN 1 ELSE 0 END) as Late_Arrivals
        FROM staging.attendance_daily a
        INNER JOIN staging.employees e ON a.emp_id = e.emp_id
        GROUP BY a.emp_id, e.full_name, e.department
        HAVING SUM(CASE WHEN a.is_late = 1 THEN 1 ELSE 0 END) > 0
        ORDER BY Late_Arrivals DESC
    """,
    "q05_overtime_reconciliation": """
        WITH PaidOT AS (
            SELECT LEFT(CAST(p.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(p.date_id AS VARCHAR), 5, 2) as payroll_month,
            emp.department, SUM(p.units) as paid_hours
            FROM warehouse.fact_payroll_line p
            INNER JOIN warehouse.dim_employee emp ON p.employee_sk = emp.employee_sk
            WHERE p.component = 'OVERTIME'
            GROUP BY LEFT(CAST(p.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(p.date_id AS VARCHAR), 5, 2), emp.department
        ),
        ApprovedOT AS (
            SELECT LEFT(CAST(o.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(o.date_id AS VARCHAR), 5, 2) as payroll_month,
            emp.department, SUM(o.approved_hours) as approved_hours
            FROM warehouse.fact_overtime_approved o
            INNER JOIN warehouse.dim_employee emp ON o.employee_sk = emp.employee_sk
            GROUP BY LEFT(CAST(o.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(o.date_id AS VARCHAR), 5, 2), emp.department
        ),
        ComputedOT AS (
            SELECT FORMAT(a.work_date, 'yyyy-MM') as payroll_month, emp.department,
            SUM(CASE WHEN a.status = 'Present' AND d.day_name != 'Sunday' AND a.check_out IS NOT NULL THEN 
                        CASE WHEN a.check_out > (CAST(a.work_date AS DATETIME) + CAST(s.end_time AS DATETIME)) 
                             THEN FLOOR((DATEDIFF(minute, CAST(a.work_date AS DATETIME) + CAST(s.end_time AS DATETIME), a.check_out)) / 30.0) * 0.5
                             ELSE 0 END
                     WHEN a.status = 'Present' AND (d.day_name = 'Sunday' OR h.holiday_name IS NOT NULL) THEN
                        FLOOR((a.worked_hours) / 0.5) * 0.5
                     ELSE 0 END) as computed_hours
            FROM staging.attendance_daily a
            INNER JOIN warehouse.dim_employee emp ON a.emp_id = emp.emp_id AND a.work_date BETWEEN emp.valid_from AND emp.valid_to
            INNER JOIN warehouse.dim_date d ON CAST(FORMAT(a.work_date, 'yyyyMMdd') AS INT) = d.date_id
            LEFT JOIN staging.shifts s ON a.shift_code = s.shift_code
            LEFT JOIN staging.holidays h ON a.work_date = h.holiday_date
            WHERE a.status = 'Present'
            GROUP BY FORMAT(a.work_date, 'yyyy-MM'), emp.department
        )
        SELECT ISNULL(p.payroll_month, ISNULL(a.payroll_month, c.payroll_month)) as Month,
        ISNULL(p.department, ISNULL(a.department, c.department)) as Department,
        ISNULL(c.computed_hours, 0) as Computed_OT_Hours, ISNULL(a.approved_hours, 0) as Approved_OT_Hours,
        ISNULL(p.paid_hours, 0) as Paid_OT_Hours, ISNULL(p.paid_hours, 0) - ISNULL(c.computed_hours, 0) as Paid_vs_Computed_Gap
        FROM PaidOT p
        FULL OUTER JOIN ApprovedOT a ON p.payroll_month = a.payroll_month AND p.department = a.department
        FULL OUTER JOIN ComputedOT c ON COALESCE(p.payroll_month, a.payroll_month) = c.payroll_month AND COALESCE(p.department, a.department) = c.department
    """,
    "q06_excess_overtime": """
        WITH PaidOT AS (
            SELECT emp.department, SUM(p.units) as paid_hours
            FROM warehouse.fact_payroll_line p
            INNER JOIN warehouse.dim_employee emp ON p.employee_sk = emp.employee_sk
            WHERE p.component = 'OVERTIME'
            GROUP BY emp.department
        ),
        ComputedOT AS (
            SELECT emp.department,
            SUM(CASE WHEN a.status = 'Present' AND d.day_name != 'Sunday' AND a.check_out > (CAST(a.work_date AS DATETIME) + CAST(s.end_time AS DATETIME)) 
                        THEN FLOOR((DATEDIFF(minute, CAST(a.work_date AS DATETIME) + CAST(s.end_time AS DATETIME), a.check_out)) / 30.0) * 0.5
                     WHEN a.status = 'Present' AND (d.day_name = 'Sunday' OR h.holiday_name IS NOT NULL) 
                        THEN FLOOR((a.worked_hours) / 0.5) * 0.5
                     ELSE 0 END) as computed_hours
            FROM staging.attendance_daily a
            INNER JOIN warehouse.dim_employee emp ON a.emp_id = emp.emp_id AND a.work_date BETWEEN emp.valid_from AND emp.valid_to
            INNER JOIN warehouse.dim_date d ON CAST(FORMAT(a.work_date, 'yyyyMMdd') AS INT) = d.date_id
            LEFT JOIN staging.shifts s ON a.shift_code = s.shift_code
            LEFT JOIN staging.holidays h ON a.work_date = h.holiday_date
            WHERE a.status = 'Present'
            GROUP BY emp.department
        )
        SELECT p.department, p.paid_hours, ISNULL(c.computed_hours, 0) as computed_hours,
        CAST((p.paid_hours - ISNULL(c.computed_hours, 0)) * 100.0 / NULLIF(c.computed_hours, 0) AS DECIMAL(10,2)) as Excess_Paid_Pct
        FROM PaidOT p INNER JOIN ComputedOT c ON p.department = c.department
        WHERE p.paid_hours > (c.computed_hours * 1.15)
    """,
    "q07_ghost_employees": """
        WITH Paid AS (
            SELECT emp_id, payroll_month as month FROM raw.payroll_lines WHERE component_type = 'EARNING'
        ),
        Attended AS (
            SELECT emp_id, FORMAT(work_date, 'yyyy-MM') as month FROM staging.attendance_daily WHERE status = 'Present'
        )
        SELECT p.emp_id, p.month FROM Paid p
        LEFT JOIN Attended a ON p.emp_id = a.emp_id AND p.month = a.month
        WHERE a.emp_id IS NULL
    """,
    "q08_pay_after_separation": """
        SELECT p.emp_id, p.payroll_month as month, e.separation_date
        FROM raw.payroll_lines p
        INNER JOIN staging.employees e ON p.emp_id = e.emp_id
        WHERE e.separation_date IS NOT NULL AND TRY_CAST(p.payroll_month + '-01' AS DATE) > e.separation_date
    """,
    "q09_payroll_cost_mom": """
        WITH MonthlyCost AS (
            SELECT FORMAT(date_id, 'yyyy-MM') as month, emp.department, SUM(p.amount) as total_cost
            FROM warehouse.fact_payroll_line p
            INNER JOIN warehouse.dim_employee emp ON p.employee_sk = emp.employee_sk
            WHERE p.component_type = 'EARNING'
            GROUP BY FORMAT(date_id, 'yyyy-MM'), emp.department
        )
        SELECT month, department, total_cost,
        total_cost - LAG(total_cost) OVER(PARTITION BY department ORDER BY month) as MoM_Change
        FROM MonthlyCost
    """,
    "q10_leave_entitlement": """
        SELECT a.emp_id, e.full_name, e.annual_leave_entitlement, COUNT(a.work_date) as Approved_Leave_Days
        FROM staging.attendance_daily a
        INNER JOIN staging.employees e ON a.emp_id = e.emp_id
        WHERE a.status = 'On Leave' 
        GROUP BY a.emp_id, e.full_name, e.annual_leave_entitlement
        HAVING COUNT(a.work_date) > e.annual_leave_entitlement
    """
}

output_dir = os.path.join(os.path.dirname(__file__), '..', 'output')
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

for name, query in queries.items():
    try:
        print(f"Running {name}...")
        df = pd.read_sql(query, engine)
        df.to_csv(os.path.join(output_dir, f"{name}.csv"), index=False)
        print(f" -> Saved {name}.csv")
    except Exception as e:
        print(f"Error in {name}: {e}")

print("🎉 All CSV Exports Completed!")
