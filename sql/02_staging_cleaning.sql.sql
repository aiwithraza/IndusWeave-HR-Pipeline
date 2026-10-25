USE IndusWeaveHR;
GO

-- 1. Staging Schema banao
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'staging')
BEGIN EXEC('CREATE SCHEMA staging'); END
GO

-- ==========================================
-- 2. EMPLOYEES CLEANING & DEDUPLICATION
-- ==========================================
DROP TABLE IF EXISTS staging.employees;
CREATE TABLE staging.employees (
    emp_id NVARCHAR(50) PRIMARY KEY, 
    full_name NVARCHAR(100), 
    hire_date DATE, 
    separation_date DATE,
    plant NVARCHAR(50), 
    department NVARCHAR(100), 
    grade NVARCHAR(10), 
    status NVARCHAR(50), 
    annual_leave_entitlement INT
);

INSERT INTO staging.employees
SELECT emp_id, full_name, 
       TRY_CAST(hire_date AS DATE), TRY_CAST(separation_date AS DATE), 
       TRIM(plant), TRIM(department), TRIM(grade), TRIM(status), TRY_CAST(annual_leave_entitlement AS INT)
FROM (
    -- Sirf latest updated_at wala record rakho
    SELECT *, ROW_NUMBER() OVER(PARTITION BY emp_id ORDER BY TRY_CAST(updated_at AS DATETIME) DESC) as rn
    FROM raw.employees
) t WHERE rn = 1;

-- ==========================================
-- 3. EMPLOYMENT HISTORY (SCD Type 2 Logic)
-- ==========================================
DROP TABLE IF EXISTS staging.employment_history;
SELECT emp_id, 
       TRY_CAST(effective_from AS DATE) as valid_from,
       -- effective_to ko ignore karke next record se ek din pehle tak valid karo
       ISNULL(DATEADD(day, -1, LEAD(TRY_CAST(effective_from AS DATE)) OVER(PARTITION BY emp_id ORDER BY TRY_CAST(effective_from AS DATE))), '9999-12-31') as valid_to,
       dept_id, designation, grade, TRY_CAST(basic_salary AS DECIMAL(18,2)) as basic_salary
INTO staging.employment_history
FROM raw.employment_history;

-- ==========================================
-- 4. BIOMETRIC PUNCHES (Faulty Device Fix)
-- ==========================================
DROP TABLE IF EXISTS staging.biometric_punches;
SELECT punch_id, device_id, device_user_id, 
       -- DEV_05 ka clock 1 ghanta aage hai, usko 1 ghanta peeche karo
       CASE WHEN device_id = 'DEV_05' THEN DATEADD(hour, -1, TRY_CAST(punch_time AS DATETIME))
            ELSE TRY_CAST(punch_time AS DATETIME) END as punch_time
INTO staging.biometric_punches
FROM raw.biometric_punches;

-- ==========================================
-- 5. OTHER TABLES CLEANING
-- ==========================================
DROP TABLE IF EXISTS staging.device_mapping;
SELECT device_id, device_user_id, emp_id
INTO staging.device_mapping
FROM raw.device_mapping;

DROP TABLE IF EXISTS staging.holidays;
SELECT TRY_CAST(holiday_date AS DATE) as holiday_date, holiday_name, scope
INTO staging.holidays FROM raw.holidays;

DROP TABLE IF EXISTS staging.shifts;
SELECT shift_code, name, start_time, end_time, 
       CASE WHEN crosses_midnight = 'True' THEN 1 ELSE 0 END as crosses_midnight, 
       grace_minutes 
INTO staging.shifts FROM raw.shifts;

DROP TABLE IF EXISTS staging.leave_requests;
SELECT request_id, emp_id, leave_type, 
       TRY_CAST(from_date AS DATE) as from_date, 
       TRY_CAST(to_date AS DATE) as to_date, 
       cancelled_at
INTO staging.leave_requests
FROM raw.leave_requests
WHERE cancelled_at = '' AND approvals_json LIKE '%Approved%';