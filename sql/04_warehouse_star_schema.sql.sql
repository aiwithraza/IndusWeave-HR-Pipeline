USE IndusWeaveHR;
GO

-- Warehouse Schema banao
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'warehouse')
BEGIN EXEC('CREATE SCHEMA warehouse'); END
GO

-- ==========================================
-- 1. DIMENSIONS BANAO
-- ==========================================

-- Dim Date
DROP TABLE IF EXISTS warehouse.dim_date;
WITH DateSeries AS (
    SELECT CAST('2026-04-01' AS DATE) as date_key
    UNION ALL
    SELECT DATEADD(day, 1, date_key) FROM DateSeries WHERE date_key < '2026-10-31'
)
SELECT 
    CAST(FORMAT(date_key, 'yyyyMMdd') AS INT) as date_id,
    date_key, 
    YEAR(date_key) as year,
    MONTH(date_key) as month,
    DATENAME(month, date_key) as month_name,
    DATENAME(weekday, date_key) as day_name,
    CASE WHEN DATENAME(weekday, date_key) = 'Sunday' THEN 1 ELSE 0 END as is_weekend
INTO warehouse.dim_date
FROM DateSeries
OPTION (MAXRECURSION 300);

-- Dim Department
DROP TABLE IF EXISTS warehouse.dim_department;
SELECT dept_id as department_id, dept_name, plant 
INTO warehouse.dim_department
FROM raw.departments;

-- Dim Shift
DROP TABLE IF EXISTS warehouse.dim_shift;
SELECT shift_code as shift_id, name as shift_name, start_time, end_time, crosses_midnight 
INTO warehouse.dim_shift
FROM staging.shifts;

-- Dim Employee (SCD Type 2 ke sath)
DROP TABLE IF EXISTS warehouse.dim_employee;
SELECT 
    ROW_NUMBER() OVER(ORDER BY eh.emp_id, eh.valid_from) as employee_sk, -- Surrogate Key
    eh.emp_id, e.full_name, e.plant, e.department, e.grade, e.status,
    eh.designation, eh.basic_salary, eh.valid_from, eh.valid_to
INTO warehouse.dim_employee
FROM staging.employment_history eh
INNER JOIN staging.employees e ON eh.emp_id = e.emp_id;

-- ==========================================
-- 2. FACTS BANAO
-- ==========================================

-- Fact Attendance Daily
DROP TABLE IF EXISTS warehouse.fact_attendance_daily;
SELECT 
    CAST(FORMAT(a.work_date, 'yyyyMMdd') AS INT) as date_id,
    emp.employee_sk,
    a.shift_code as shift_id,
    a.status,
    a.worked_hours,
    a.is_late,
    a.is_early
INTO warehouse.fact_attendance_daily
FROM staging.attendance_daily a
INNER JOIN warehouse.dim_employee emp 
    ON a.emp_id = emp.emp_id 
    AND a.work_date BETWEEN emp.valid_from AND emp.valid_to;

-- Fact Payroll Lines
DROP TABLE IF EXISTS warehouse.fact_payroll_line;
SELECT 
    p.line_id,
    emp.employee_sk,
    CAST(REPLACE(p.payroll_month, '-', '') + '01' AS INT) as date_id,
    p.component,
    p.component_type,
    CAST(p.units AS DECIMAL(10,2)) as units,
    CAST(p.amount AS DECIMAL(18,2)) as amount
INTO warehouse.fact_payroll_line
FROM raw.payroll_lines p
INNER JOIN warehouse.dim_employee emp 
    ON p.emp_id = emp.emp_id 
    AND CAST(p.payroll_month + '-01' AS DATE) BETWEEN emp.valid_from AND emp.valid_to;

-- Fact Overtime Approved
DROP TABLE IF EXISTS warehouse.fact_overtime_approved;
SELECT 
    o.request_id,
    emp.employee_sk,
    CAST(FORMAT(TRY_CAST(o.ot_date AS DATE), 'yyyyMMdd') AS INT) as date_id,
    CAST(o.approved_hours AS DECIMAL(10,2)) as approved_hours
INTO warehouse.fact_overtime_approved
FROM raw.overtime_requests o
INNER JOIN warehouse.dim_employee emp 
    ON o.emp_id = emp.emp_id 
    AND TRY_CAST(o.ot_date AS DATE) BETWEEN emp.valid_from AND emp.valid_to
WHERE o.status = 'Approved';

PRINT 'Stage 4: Star Schema Created Successfully! 🎉';