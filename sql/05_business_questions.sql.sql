USE IndusWeaveHR;
GO

-- Q5 FIXED: Overtime computed vs approved vs paid
WITH PaidOT AS (
    SELECT 
        LEFT(CAST(p.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(p.date_id AS VARCHAR), 5, 2) as payroll_month,
        emp.department,
        SUM(p.units) as paid_hours
    FROM warehouse.fact_payroll_line p
    INNER JOIN warehouse.dim_employee emp ON p.employee_sk = emp.employee_sk
    WHERE p.component = 'OVERTIME'
    GROUP BY LEFT(CAST(p.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(p.date_id AS VARCHAR), 5, 2), emp.department
),
ApprovedOT AS (
    SELECT 
        LEFT(CAST(o.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(o.date_id AS VARCHAR), 5, 2) as payroll_month,
        emp.department,
        SUM(o.approved_hours) as approved_hours
    FROM warehouse.fact_overtime_approved o
    INNER JOIN warehouse.dim_employee emp ON o.employee_sk = emp.employee_sk
    GROUP BY LEFT(CAST(o.date_id AS VARCHAR), 4) + '-' + SUBSTRING(CAST(o.date_id AS VARCHAR), 5, 2), emp.department
),
ComputedOT AS (
    SELECT 
        FORMAT(a.work_date, 'yyyy-MM') as payroll_month,
        emp.department,
        SUM(
            CASE 
                -- Working day par shift end ke baad ka time
                WHEN a.status = 'Present' AND d.day_name != 'Sunday' AND a.check_out IS NOT NULL THEN 
                    CASE WHEN a.check_out > (CAST(a.work_date AS DATETIME) + CAST(s.end_time AS DATETIME)) 
                         THEN FLOOR((DATEDIFF(minute, CAST(a.work_date AS DATETIME) + CAST(s.end_time AS DATETIME), a.check_out)) / 30.0) * 0.5
                         ELSE 0 END
                -- Sunday ya Holiday par pura time
                WHEN a.status = 'Present' AND (d.day_name = 'Sunday' OR h.holiday_name IS NOT NULL) THEN
                    FLOOR((a.worked_hours) / 0.5) * 0.5
                ELSE 0 
            END
        ) as computed_hours
    FROM staging.attendance_daily a
    INNER JOIN warehouse.dim_employee emp 
        ON a.emp_id = emp.emp_id 
        AND a.work_date BETWEEN emp.valid_from AND emp.valid_to
    INNER JOIN warehouse.dim_date d ON CAST(FORMAT(a.work_date, 'yyyyMMdd') AS INT) = d.date_id
    LEFT JOIN staging.shifts s ON a.shift_code = s.shift_code
    LEFT JOIN staging.holidays h ON a.work_date = h.holiday_date
    WHERE a.status = 'Present'
    GROUP BY FORMAT(a.work_date, 'yyyy-MM'), emp.department
)
SELECT 
    ISNULL(p.payroll_month, ISNULL(a.payroll_month, c.payroll_month)) as Month,
    ISNULL(p.department, ISNULL(a.department, c.department)) as Department,
    ISNULL(c.computed_hours, 0) as Computed_OT_Hours,
    ISNULL(a.approved_hours, 0) as Approved_OT_Hours,
    ISNULL(p.paid_hours, 0) as Paid_OT_Hours,
    ISNULL(p.paid_hours, 0) - ISNULL(c.computed_hours, 0) as Paid_vs_Computed_Gap
FROM PaidOT p
FULL OUTER JOIN ApprovedOT a ON p.payroll_month = a.payroll_month AND p.department = a.department
FULL OUTER JOIN ComputedOT c ON COALESCE(p.payroll_month, a.payroll_month) = c.payroll_month AND COALESCE(p.department, a.department) = c.department
ORDER BY Month, Department;