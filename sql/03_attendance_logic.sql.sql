USE IndusWeaveHR;
GO

-- ==========================================
-- Stage 3: Attendance Daily Logic
-- ==========================================

-- 1. Shift roster ka gap fill karein (Missing week = previous week shift)
DROP TABLE IF EXISTS staging.shift_roster_filled;
WITH RosterFilled AS (
    SELECT emp_id, TRY_CAST(week_start AS DATE) as week_start, shift_code,
           LAG(shift_code) OVER(PARTITION BY emp_id ORDER BY TRY_CAST(week_start AS DATE)) as prev_shift
    FROM raw.shift_roster
)
SELECT emp_id, week_start, ISNULL(shift_code, prev_shift) as shift_code
INTO staging.shift_roster_filled
FROM RosterFilled;

-- 2. Punches ko clean karein (2-minute rule) aur Shift Date assign karein
DROP TABLE IF EXISTS staging.clean_punches;
WITH DedupedPunches AS (
    SELECT p.device_user_id, m.emp_id, p.punch_time,
           -- Night shift ka punch (agar subah 6 baje se pehle hai) toh pichle din ka maana jayega
           TRY_CAST(
               CASE WHEN CAST(p.punch_time AS TIME) < '06:00:00' 
                    THEN DATEADD(day, -1, CAST(p.punch_time AS DATE))
                    ELSE CAST(p.punch_time AS DATE) END AS DATE
           ) as shift_date,
           LAG(p.punch_time) OVER(PARTITION BY m.emp_id ORDER BY p.punch_time) as prev_punch
    FROM staging.biometric_punches p
    INNER JOIN staging.device_mapping m ON p.device_id = m.device_id AND p.device_user_id = m.device_user_id
)
SELECT emp_id, shift_date, 
       MIN(punch_time) as check_in, 
       MAX(punch_time) as check_out,
       COUNT(*) as punch_count
INTO staging.clean_punches
FROM DedupedPunches
WHERE prev_punch IS NULL OR DATEDIFF(minute, prev_punch, punch_time) > 2
GROUP BY emp_id, shift_date;

-- 3. Attendance Daily banao
DROP TABLE IF EXISTS staging.attendance_daily;
WITH Calendar AS (
    -- April 1 to Sept 30 tak ka calendar
    SELECT CAST('2026-04-01' AS DATE) as work_date
    UNION ALL
    SELECT DATEADD(day, 1, work_date) FROM Calendar WHERE work_date < '2026-09-30'
),
EmployeeDays AS (
    SELECT e.emp_id, e.plant, c.work_date, 
           DATENAME(weekday, c.work_date) as day_name,
           r.shift_code, s.start_time, s.end_time, s.crosses_midnight,
           p.check_in, p.check_out, p.punch_count,
           l.leave_type,
           h.holiday_name
    FROM staging.employees e
    CROSS JOIN Calendar c
    LEFT JOIN staging.shift_roster_filled r ON e.emp_id = r.emp_id AND c.work_date BETWEEN r.week_start AND DATEADD(day, 6, r.week_start)
    LEFT JOIN staging.shifts s ON r.shift_code = s.shift_code
    LEFT JOIN staging.clean_punches p ON e.emp_id = p.emp_id AND c.work_date = p.shift_date
    LEFT JOIN staging.leave_requests l ON e.emp_id = l.emp_id AND c.work_date BETWEEN l.from_date AND l.to_date
    LEFT JOIN staging.holidays h ON c.work_date = h.holiday_date AND (h.scope = 'ALL' OR (h.scope = 'HO' AND e.plant = 'Head Office') OR (h.scope = 'KOR' AND e.plant = 'Korangi Plant') OR (h.scope = 'SITE' AND e.plant = 'SITE Plant') OR (h.scope = 'FSD' AND e.plant = 'Faisalabad Plant'))
    WHERE c.work_date >= e.hire_date AND (e.separation_date IS NULL OR c.work_date <= e.separation_date)
)
SELECT 
    emp_id, plant, work_date, shift_code,
    check_in, check_out,
    -- Status Logic
    CASE 
        WHEN day_name = 'Sunday' AND punch_count IS NULL THEN 'Weekly Off'
        WHEN holiday_name IS NOT NULL AND punch_count IS NULL THEN 'Holiday'
        WHEN leave_type IS NOT NULL AND punch_count IS NULL THEN 'On Leave'
        WHEN punch_count >= 2 THEN 'Present'
        WHEN punch_count = 1 THEN 'Missing Punch'
        ELSE 'Absent'
    END as status,
    -- Worked Hours
    CASE WHEN punch_count >= 2 THEN DATEDIFF(minute, check_in, check_out) / 60.0 ELSE 0 END as worked_hours,
    -- Late Arrival
    CASE WHEN punch_count >= 2 AND DATEDIFF(minute, CAST(work_date AS DATETIME) + CAST(start_time AS DATETIME), check_in) > 10 THEN 1 ELSE 0 END as is_late,
    -- Early Departure
    CASE WHEN punch_count >= 2 AND DATEDIFF(minute, check_out, CAST(work_date AS DATETIME) + CAST(end_time AS DATETIME)) > 10 THEN 1 ELSE 0 END as is_early
INTO staging.attendance_daily
FROM EmployeeDays
OPTION (MAXRECURSION 200);