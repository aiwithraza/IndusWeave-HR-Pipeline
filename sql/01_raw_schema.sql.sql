USE IndusWeaveHR;
GO

-- Pehle purani tables ko delete karein (agar bani hui hain toh)
IF OBJECT_ID('raw.load_log', 'U') IS NOT NULL DROP TABLE raw.load_log;
IF OBJECT_ID('raw.shifts', 'U') IS NOT NULL DROP TABLE raw.shifts;
IF OBJECT_ID('raw.applications', 'U') IS NOT NULL DROP TABLE raw.applications;
IF OBJECT_ID('raw.payroll_lines', 'U') IS NOT NULL DROP TABLE raw.payroll_lines;
IF OBJECT_ID('raw.overtime_requests', 'U') IS NOT NULL DROP TABLE raw.overtime_requests;
IF OBJECT_ID('raw.leave_requests', 'U') IS NOT NULL DROP TABLE raw.leave_requests;
IF OBJECT_ID('raw.holidays', 'U') IS NOT NULL DROP TABLE raw.holidays;
IF OBJECT_ID('raw.biometric_punches', 'U') IS NOT NULL DROP TABLE raw.biometric_punches;
IF OBJECT_ID('raw.device_mapping', 'U') IS NOT NULL DROP TABLE raw.device_mapping;
IF OBJECT_ID('raw.shift_roster', 'U') IS NOT NULL DROP TABLE raw.shift_roster;
IF OBJECT_ID('raw.departments', 'U') IS NOT NULL DROP TABLE raw.departments;
IF OBJECT_ID('raw.employment_history', 'U') IS NOT NULL DROP TABLE raw.employment_history;
IF OBJECT_ID('raw.employees', 'U') IS NOT NULL DROP TABLE raw.employees;
GO

-- Ab naye sire se tables banayein
CREATE TABLE raw.employees (
    emp_id NVARCHAR(50), full_name NVARCHAR(100), gender NVARCHAR(20), email NVARCHAR(100), phone NVARCHAR(50),
    date_of_birth NVARCHAR(50), hire_date NVARCHAR(50), separation_date NVARCHAR(50),
    plant NVARCHAR(50), department NVARCHAR(100), designation NVARCHAR(100), grade NVARCHAR(10),
    employment_type NVARCHAR(50), status NVARCHAR(50), annual_leave_entitlement NVARCHAR(10), updated_at NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.employment_history (
    emp_id NVARCHAR(50), effective_from NVARCHAR(50), effective_to NVARCHAR(50), dept_id NVARCHAR(50),
    designation NVARCHAR(100), grade NVARCHAR(10), basic_salary NVARCHAR(50), change_reason NVARCHAR(100),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.departments (
    dept_id NVARCHAR(50), dept_name NVARCHAR(100), plant NVARCHAR(50), cost_center NVARCHAR(50), previous_name NVARCHAR(100), renamed_on NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.shift_roster (
    emp_id NVARCHAR(50), week_start NVARCHAR(50), shift_code NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.device_mapping (
    device_id NVARCHAR(50), device_user_id NVARCHAR(50), emp_id NVARCHAR(50), enrolled_on NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.biometric_punches (
    punch_id NVARCHAR(50), device_id NVARCHAR(50), device_user_id NVARCHAR(50), punch_time NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.holidays (
    holiday_date NVARCHAR(50), holiday_name NVARCHAR(100), scope NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.leave_requests (
    request_id NVARCHAR(50), emp_id NVARCHAR(50), plant NVARCHAR(50), leave_type NVARCHAR(100),
    from_date NVARCHAR(50), to_date NVARCHAR(50), days_requested NVARCHAR(50), submitted_at NVARCHAR(50),
    cancelled_at NVARCHAR(50), approvals_json NVARCHAR(MAX),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.overtime_requests (
    request_id NVARCHAR(50), emp_id NVARCHAR(50), ot_date NVARCHAR(50), requested_hours NVARCHAR(50),
    approved_hours NVARCHAR(50), status NVARCHAR(50), approver_id NVARCHAR(50), requested_at NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.payroll_lines (
    line_id NVARCHAR(50), payroll_month NVARCHAR(50), emp_id NVARCHAR(50), component NVARCHAR(50),
    component_type NVARCHAR(50), units NVARCHAR(50), amount NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.applications (
    application_id NVARCHAR(50), candidate_id NVARCHAR(50), job_req_id NVARCHAR(50), dept_id NVARCHAR(50),
    stage NVARCHAR(50), stage_date NVARCHAR(50),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.shifts (
    shift_code NVARCHAR(50), shift_name NVARCHAR(100), start_time NVARCHAR(50), end_time NVARCHAR(50), crosses_midnight NVARCHAR(10),
    _source_file NVARCHAR(100), _loaded_at DATETIME DEFAULT GETDATE(), _row_hash CHAR(32)
);

CREATE TABLE raw.load_log (
    load_id INT IDENTITY(1,1) PRIMARY KEY,
    source_file NVARCHAR(100),
    target_table NVARCHAR(100),
    raw_row_count INT,
    loaded_row_count INT,
    loaded_at DATETIME DEFAULT GETDATE()
);
GO