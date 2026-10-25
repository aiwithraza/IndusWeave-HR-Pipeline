USE IndusWeaveHR;
GO

-- Fact Attendance Daily (Yeh pehle se ban gaya hai agar error ke baad ruka tha, lekin dobara bana rahe hain)
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

-- Fact Payroll Lines (Yahan humne filter laga diya hai ke sirf valid months uthaye jayein)
DROP TABLE IF EXISTS warehouse.fact_payroll_line;
SELECT 
    p.line_id,
    emp.employee_sk,
    CAST(REPLACE(p.payroll_month, '-', '') + '01' AS INT) as date_id,
    p.component,
    p.component_type,
    TRY_CAST(p.units AS DECIMAL(10,2)) as units,
    TRY_CAST(p.amount AS DECIMAL(18,2)) as amount
INTO warehouse.fact_payroll_line
FROM raw.payroll_lines p
INNER JOIN warehouse.dim_employee emp 
    ON p.emp_id = emp.emp_id 
    AND TRY_CAST(p.payroll_month + '-01' AS DATE) BETWEEN emp.valid_from AND emp.valid_to
WHERE p.payroll_month LIKE '____-__'; -- Sirf sahi format wale months uthao

-- Fact Overtime Approved
DROP TABLE IF EXISTS warehouse.fact_overtime_approved;
SELECT 
    o.request_id,
    emp.employee_sk,
    CAST(FORMAT(TRY_CAST(o.ot_date AS DATE), 'yyyyMMdd') AS INT) as date_id,
    TRY_CAST(o.approved_hours AS DECIMAL(10,2)) as approved_hours
INTO warehouse.fact_overtime_approved
FROM raw.overtime_requests o
INNER JOIN warehouse.dim_employee emp 
    ON o.emp_id = emp.emp_id 
    AND TRY_CAST(o.ot_date AS DATE) BETWEEN emp.valid_from AND emp.valid_to
WHERE o.status = 'Approved' AND o.ot_date IS NOT NULL;

PRINT 'Stage 4: Fact Tables Created Successfully! 🎉';