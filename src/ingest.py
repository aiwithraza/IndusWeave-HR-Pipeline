import sys, os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import pandas as pd
import hashlib
import json
from sqlalchemy import text
from config import get_engine, RAW_DATA_PATH
from datetime import datetime

engine = get_engine()

def generate_hash(row):
    return hashlib.md5("".join([str(v) for v in row.values]).encode('utf-8')).hexdigest()

def load_csv(f_name, t_name):
    print(f"Loading {f_name}...")
    df = pd.read_csv(os.path.join(RAW_DATA_PATH, f_name), dtype=str, keep_default_na=False)
    raw_count = len(df)
    df['_source_file'] = f_name
    df['_loaded_at'] = datetime.now()
    df['_row_hash'] = df.apply(generate_hash, axis=1)
    
    with engine.connect() as conn:
        existing = pd.read_sql(f"SELECT _row_hash FROM raw.{t_name}", conn)['_row_hash'].tolist()
    new_df = df[~df['_row_hash'].isin(existing)]
    
    if len(new_df) > 0:
        new_df.to_sql(t_name, engine, schema='raw', if_exists='append', index=False)
    
    with engine.begin() as conn:
        conn.execute(text(f"INSERT INTO raw.load_log (source_file, target_table, raw_row_count, loaded_row_count) VALUES ('{f_name}', 'raw.{t_name}', {raw_count}, {len(new_df)})"))
    print(f" -> Loaded {len(new_df)} rows into raw.{t_name}")

if __name__ == "__main__":
    files = [('employees.csv', 'employees'), ('employment_history.csv', 'employment_history'), 
             ('departments.csv', 'departments'), ('shift_roster.csv', 'shift_roster'), 
             ('device_mapping.csv', 'device_mapping'), ('biometric_punches.csv', 'biometric_punches'), 
             ('holidays.csv', 'holidays'), ('overtime_requests.csv', 'overtime_requests'), 
             ('payroll_lines.csv', 'payroll_lines'), ('applications.csv', 'applications')]
    for f, t in files: load_csv(f, t)
    
    print("Loading JSONs...")
    
    # SHIFTS JSON FIX
    with open(os.path.join(RAW_DATA_PATH, 'shifts.json')) as f: 
        shifts_data = json.load(f)
    df_s = pd.DataFrame(shifts_data['shifts']) 
    df_s['_source_file'] = 'shifts.json'
    df_s['_loaded_at'] = datetime.now()
    df_s['_row_hash'] = df_s.apply(generate_hash, axis=1)
    df_s.to_sql('shifts', engine, schema='raw', if_exists='replace', index=False)
    print(f" -> Loaded {len(df_s)} shifts.")

    # LEAVE REQUESTS JSON
    with open(os.path.join(RAW_DATA_PATH, 'leave_requests.json')) as f: 
        leaves = json.load(f)
    flat = [{'request_id':r.get('request_id'),'emp_id':r['employee']['emp_id'],'leave_type':r['leave'].get('type'),'from_date':r['leave'].get('from'),'to_date':r['leave'].get('to'),'cancelled_at':r.get('cancelled_at'),'approvals_json':json.dumps(r.get('approvals',[]))} for r in leaves]
    df_l = pd.DataFrame(flat); df_l['_source_file']='leave_requests.json'; df_l['_loaded_at']=datetime.now(); df_l['_row_hash']=df_l.apply(generate_hash, axis=1)
    df_l.to_sql('leave_requests', engine, schema='raw', if_exists='replace', index=False)
    print(f" -> Loaded {len(df_l)} leave requests.")
    
    print("🎉 Ingestion Complete! Data is in Raw Schema.")