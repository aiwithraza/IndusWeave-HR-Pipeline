# PeopleOps Data Hackathon: HR Pipeline Case Study

**Author:** Muhammad Raza

## 📌 Project Overview
This project is a complete data pipeline built in Python and Microsoft SQL Server (MSSQL). It transforms six months of messy HR exports (from Indus Weave Textiles) into a trusted Star Schema data warehouse. The goal is to reconcile attendance, shifts, leave, and payroll data to explain why the overtime bill keeps rising.

## 🛠️ Tech Stack
- **Database:** Microsoft SQL Server (MSSQL)
- **Programming Language:** Python 3 (Pandas, SQLAlchemy, pyodbc)
- **Data Modeling:** Star Schema with SCD Type 2 for Employee Dimension

## 🏗️ Pipeline Architecture (6 Stages)
1. **Ingestion (Python):** Loads 12 raw CSV/JSON files into the `raw` schema as text, with idempotency (using `_row_hash`) and load logs.
2. **Cleaning & Standardization (SQL):** Fixes mixed date formats, deduplicates employees, detects and corrects the faulty biometric device (`DEV_05`), and cleans nested JSON leave requests.
3. **Attendance Logic (SQL):** Reconstructs shift pairings, applies the 2-minute punch rule, calculates late minutes, early departures, and actual computed overtime (handling night shifts and Sundays).
4. **Warehouse Modeling (SQL):** Builds a Star Schema with `dim_employee` (SCD2), `dim_date`, `dim_department`, `dim_shift` and `fact_attendance_daily`, `fact_payroll_line`, `fact_overtime_approved`.
5. **Business Questions (SQL):** 10 SQL scripts answering critical business questions from headcount to ghost employees.
6. **Data Quality (SQL):** Automated checks for PK uniqueness, Referential Integrity, and business sanity (e.g., no shift > 16 hours).

## 🔍 Top 3 CFO Findings
1. **Overtime Leakage:** Certain departments (e.g., Human Resources, Production Planning) are being paid significantly more Overtime than what is actually computed from biometric punches. 
2. **Faulty Biometric Device:** Device `DEV_05` had a clock running 1 hour ahead, causing inaccurate punch times.
3. **Ghost Employees:** Some employees are receiving payroll earnings in months where they have zero recorded attendance in the biometric system.

## 📂 Project Structure
- `src/`: Python ingestion script (`ingest.py`).
- `sql/`: Contains all SQL scripts from raw schema creation to business questions and data quality checks.
- `output/`: Contains CSV exports of the results from the 10 business questions.
- `ER_Diagram.png`: Visual representation of the Star Schema.
- `config.py`: Database connection settings.

## 🚀 How to Run
1. Create the database: `CREATE DATABASE IndusWeaveHR;`
2. Run SQL scripts in order from `01_raw_schema.sql` to `06_data_quality_and_findings.sql` in your SQL Server.
3. Update `config.py` with your SQL Server credentials.
4. Run the Python ingestion: `python src/ingest.py`
